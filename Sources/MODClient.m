//
//  MODClient.m
//  MongoObjCDriver
//
//  Created by Jérôme Lebel on 02/09/2011.
//

#import "MongoObjCDriver-private.h"
#import "bson.h"
#import "mongoc.h"
#import "mongoc-client-private.h"

@interface MODBlockOperation : NSBlockOperation
{
    MODQuery *_mongoQuery;
}
@property (nonatomic, readwrite, strong) MODQuery *mongoQuery;

@end

@implementation MODBlockOperation

@synthesize mongoQuery = _mongoQuery;

- (void)dealloc
{
    self.mongoQuery = nil;
    [super dealloc];
}

@end

@interface MODClient ()
@property (nonatomic, strong, readwrite) NSOperationQueue *operationQueue;
@property (nonatomic, strong, readwrite) NSMutableArray *mongoQueries;


@end

@implementation MODClient

@synthesize connected = _connected;
@synthesize mongocClient = _mongocClient;
@synthesize operationQueue = _operationQueue;
@synthesize mongoQueries = _mongoQueries;
@synthesize sshMapping = _sshMapping;

+ (instancetype)clientWihtURLString:(NSString *)urlString
{
    MODClient *result;
    
    mongoc_init();
    result = [[MODClient alloc] initWithURIString:urlString];
    return [result autorelease];
}

+ (uint16_t)defaultPort
{
    return MONGOC_DEFAULT_PORT;
}

+ (uint32_t)defaultConnectionTimeout
{
    return MONGOC_DEFAULT_CONNECTTIMEOUTMS;
}

- (instancetype)init
{
    if ((self = [super init]) != nil) {
        self.operationQueue = [[[NSOperationQueue alloc] init] autorelease];
        self.mongoQueries = [NSMutableArray array];
        [self.operationQueue setMaxConcurrentOperationCount:1];
    }
    return self;
}

- (instancetype)initWithURIString:(NSString *)urlString
{
    return [self initWithURICString:urlString.UTF8String];
}

- (instancetype)initWithURICString:(const char *)urlCString
{
    if ((self = [self init]) != nil) {
        self.mongocClient = mongoc_client_new(urlCString);
        if (self.mongocClient == NULL) {
            [self release];
            self = nil;
        }
        [self setupMongocClient];
    }
    return self;
}

- (instancetype)initWithMongoURI:(const mongoc_uri_t *)uri
{
    if ((self = [self init]) != nil) {
        _mongocClient = mongoc_client_new_from_uri(uri);
        if (_mongocClient == NULL) {
            [self release];
            self = nil;
        }
        [self setupMongocClient];
    }
    return self;
}

- (void)dealloc
{
    self.sslOptions = nil;
    self.writeConcern = nil;
    self.readPreferences = nil;
    self.operationQueue = nil;
    self.mongoQueries = nil;
    self.sshMapping = nil;
    mongoc_client_destroy(self.mongocClient);
    [super dealloc];
}

- (instancetype)copy
{
    MODClient *result;
    
    result = [[self.class alloc] initWithMongoURI:mongoc_client_get_uri(self.mongocClient)];
    result.sslOptions = self.sslOptions;
    result.readPreferences = self.readPreferences;
    result.writeConcern = self.writeConcern;
    return result;
}

static mongoc_stream_t *stream_initiator(const mongoc_uri_t *uri, const mongoc_host_list_t *host, void *user_data, bson_error_t *error)
{
    return [(MODClient *)user_data getStreamWithURI:uri host:host error:error];
}

- (mongoc_stream_t *)getStreamWithURI:(const mongoc_uri_t *)uri host:(const mongoc_host_list_t *)host error:(bson_error_t *)error
{
    NSString *hostPortString = [NSString stringWithUTF8String:host->host_and_port];
    NSNumber *sshBindedPort = self.sshMapping[hostPortString];
    
    if (!sshBindedPort) {
        return ((mongoc_stream_initiator_t)_defaultStreamInitiator)(uri, host, _defaultStreamInitiatorData, error);
    } else {
        mongoc_host_list_t mappedHost;
        NSArray *components = [hostPortString componentsSeparatedByString:@":"];
        
        NSAssert(components.count == 2, @"Should have ip and port in %@", hostPortString);
        memcpy(&mappedHost, host, sizeof(mappedHost));
        sprintf(mappedHost.host_and_port, "127.0.0.1:%d", (int)sshBindedPort.integerValue);
        sprintf(mappedHost.host, "127.0.0.1");
        mappedHost.port = sshBindedPort.integerValue;
        return ((mongoc_stream_initiator_t)_defaultStreamInitiator)(uri, &mappedHost, _defaultStreamInitiatorData, error);
    }
}

- (void)setupMongocClient
{
    _defaultStreamInitiator = self.mongocClient->initiator;
    _defaultStreamInitiatorData = self.mongocClient->initiator_data;
    mongoc_client_set_stream_initiator(self.mongocClient, stream_initiator, self);
}

- (MODQuery *)addQueryInQueue:(void (^)(MODQuery *currentMongoQuery))block owner:(id<NSObject>)owner name:(NSString *)name parameters:(NSDictionary *)parameters
{
    MODQuery *mongoQuery;
    MODBlockOperation *blockOperation;
    
    mongoQuery = [[MODQuery alloc] initWithOwner:owner name:name parameters:parameters];
    blockOperation = [[MODBlockOperation alloc] init];
    blockOperation.mongoQuery = mongoQuery;
    [blockOperation addExecutionBlock:^{
        [mongoQuery starts];
        block(mongoQuery);
    }];
    mongoQuery.blockOperation = blockOperation;
    [self.operationQueue addOperation:blockOperation];
    [self.mongoQueries addObject:mongoQuery];
    [blockOperation release];
    return [mongoQuery autorelease];
}

- (void)cancelAllOperations
{
    for (MODQuery *mongoQuery in self.mongoQueries) {
        [mongoQuery cancel];
    }
}

- (void)mongoQueryDidFinish:(MODQuery *)mongoQuery withError:(NSError *)error callbackBlock:(void (^)(void))callbackBlock
{
    [mongoQuery endsWithError:error];
    dispatch_async(dispatch_get_main_queue(), ^() {
        if (callbackBlock) callbackBlock();
        [self.mongoQueries removeObject:mongoQuery];
    });
}

- (void)mongoQueryDidFinish:(MODQuery *)mongoQuery withBsonError:(bson_error_t)bsonError callbackBlock:(void (^)(void))callbackBlock
{
    NSError *error = nil;
    
    if (bsonError.code != 0) {
        error = [self.class errorFromBsonError:bsonError];
    }
    [self mongoQueryDidFinish:mongoQuery withError:error callbackBlock:callbackBlock];
}

- (MODQuery *)serverStatusWithReadPreferences:(MODReadPreferences *)readPreferences callback:(void (^)(MODSortedMutableDictionary *serverStatus, MODQuery *mongoQuery))callback
{
    MODQuery *query;
    
    query = [self addQueryInQueue:^(MODQuery *mongoQuery){
        bson_t output = BSON_INITIALIZER;
        bson_error_t error = BSON_NO_ERROR;
        MODSortedMutableDictionary *outputObjects = nil;
        
        if (!mongoQuery.isCanceled) {
            mongoc_client_get_server_status(self.mongocClient, readPreferences?readPreferences.mongocReadPreferences:NULL, &output, &error);
            outputObjects = [self.class objectFromBson:&output];
        }
        [self mongoQueryDidFinish:mongoQuery withBsonError:error callbackBlock:^(void) {
            if (!mongoQuery.isCanceled && callback) {
                callback(outputObjects, mongoQuery);
            }
        }];
        bson_destroy(&output);
    } owner:self name:@"serverstatus" parameters:nil];
    return query;
}

- (MODQuery *)databaseNamesWithCallback:(void (^)(NSArray *list, MODQuery *mongoQuery))callback;
{
    MODQuery *query;
    
    query = [self addQueryInQueue:^(MODQuery *mongoQuery) {
        bson_t output = BSON_INITIALIZER;
        NSMutableArray *list = nil;
        bson_error_t error = BSON_NO_ERROR;
        
        if (!mongoQuery.isCanceled) {
            char **cStringName;
            
            cStringName = mongoc_client_get_database_names(self.mongocClient, &error);
            if (cStringName) {
                char **cursor = cStringName;
                
                list = [[NSMutableArray alloc] init];
                while (*cursor != NULL) {
                    [list addObject:[NSString stringWithUTF8String:*cursor]];
                    bson_free(*cursor);
                    cursor++;
                }
                bson_free(cStringName);
            }

        }
        [self mongoQueryDidFinish:mongoQuery withBsonError:error callbackBlock:^(void) {
            if (!mongoQuery.isCanceled && callback) {
                callback(list, mongoQuery);
            }
        }];
        bson_destroy(&output);
        [list release];
    } owner:self name:@"databasenames" parameters:nil];
    return query;
}

- (MODDatabase *)databaseForName:(NSString *)databaseName
{
    MODDatabase *result;
    
    result = [[[MODDatabase alloc] initWithClient:self name:databaseName] autorelease];
    result.readPreferences = self.readPreferences;
    return result;
}

- (mongoc_read_prefs_t *)mongocReadPreferences
{
    return self.readPreferences.mongocReadPreferences;
}

- (MODReadPreferences *)readPreferences
{
    return [MODReadPreferences readPreferencesWithMongocReadPreferences:mongoc_client_get_read_prefs(self.mongocClient)];
}

- (void)setReadPreferences:(MODReadPreferences *)readPreferences
{
    mongoc_client_set_read_prefs(self.mongocClient, self.mongocReadPreferences);
}

- (MODSSLOptions *)sslOptions
{
    return [MODSSLOptions sslOptionsWithMongocSSLOpt:&self.mongocClient->ssl_opts];
}

- (void)setSslOptions:(MODSSLOptions *)sslOptions
{
    mongoc_ssl_opt_t mongocSSLOptions = { NULL, NULL, NULL, NULL, NULL, false };
    
    [sslOptions getMongocSSLOpt:&mongocSSLOptions];
    [_sslOptions release];
    _sslOptions = [sslOptions retain];
    mongoc_client_set_ssl_opts(self.mongocClient, &mongocSSLOptions);
}

- (MODWriteConcern *)writeConcern
{
    return [MODWriteConcern writeConcernWithMongocWriteConcern:mongoc_client_get_write_concern(self.mongocClient)];
}

- (void)setWriteConcern:(MODWriteConcern *)writeConcern
{
    mongoc_client_set_write_concern(self.mongocClient, writeConcern.mongocWriteConcern);
}

@end