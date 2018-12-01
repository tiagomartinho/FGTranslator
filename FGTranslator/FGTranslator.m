//
//  FGTranslator.m
//  Fargate
//
//  Created by George Polak on 1/14/13.
//
//

#import "FGTranslator.h"
#import "FGTranslateRequest.h"
#import "NSString+FGTranslator.h"
#import "AFNetworking.h"
#import "PINCache.h"

typedef NSInteger FGTranslatorState;

enum FGTranslatorState
{
    FGTranslatorStateInitial = 0,
    FGTranslatorStateInProgress = 1,
    FGTranslatorStateCompleted = 2
};

typedef enum : NSUInteger {
    FGTranslatorServiceTypeGoogle,
    FGTranslatorServiceTypeMicrosoft,
    FGTranslatorServiceTypeUnknown,
} FGTranslatorServiceType;

float const FGTranslatorUnknownConfidence = -1;

@interface FGTranslator()
{
}

@property (nonatomic) NSString *googleAPIKey;
@property (nonatomic) NSString *azureClientId;
@property (nonatomic) NSString *azureClientSecret;

@property (nonatomic) FGTranslatorState translatorState;

@property (nonatomic) AFHTTPRequestOperation *operation;
@property (nonatomic, copy) FGTranslatorCompletionHandler completionHandler;

@end


@implementation FGTranslator

- (id)initWithGoogleAPIKey:(NSString *)key
{
    self = [self initGeneric];
    if (self)
    {
        self.googleAPIKey = key;
    }
    
    return self;
}

- (id)initWithBingAzureClientId:(NSString *)clientId secret:(NSString *)secret
{
    self = [self initGeneric];
    if (self)
    {
        self.azureClientId = clientId;
        self.azureClientSecret = secret;
    }
    
    return self;
}

- (id)initGeneric
{
    self = [super init];
    if (self)
    {
        self.preferSourceGuess = YES;
        self.translatorState = FGTranslatorStateInitial;
        
        // limit translation cache to 5 MB
        PINCache *cache = [PINCache sharedCache];
        cache.diskCache.byteLimit = 5000000;
    }
    
    return self;
}

+ (void)flushCredentials
{
    [FGTranslateRequest flushCredentials];
}

+ (void)flushCache
{
    [[PINCache sharedCache] removeAllObjects];
}

- (NSString *)cacheKeyForText:(NSString *)text target:(NSString *)target
{
    NSParameterAssert(text);
    
    NSMutableString *cacheKey = [NSMutableString stringWithString:text];
    
    if (target) {
        [cacheKey appendFormat:@"|%@", target];
    }
    
    switch (self.translationServiceType) {
        case FGTranslatorServiceTypeGoogle:
            [cacheKey appendFormat:@"|Google"];
            break;
        case FGTranslatorServiceTypeMicrosoft:
            [cacheKey appendFormat:@"|Azure"];
            break;
    }
    
    return cacheKey;
}

- (void)cacheText:(NSString *)text translated:(NSString *)translated source:(NSString *)source target: (NSString *)target
{
    if (!text || !translated)
        return;
    
    NSMutableDictionary *cached = [NSMutableDictionary new];
    [cached setObject:translated forKey:@"txt"];
    if (source)
        [cached setObject:source forKey:@"src"];
    
    [[PINCache sharedCache] setObject:cached forKey:[self cacheKeyForText:text target:target]];
}

- (void)translateText:(NSString *)text
           completion:(FGTranslatorCompletionHandler)completion
{
    [self translateText:text withSource:nil target:nil completion:completion];
}

- (void)translateTexts:(NSArray <NSString*> *)texts
            withSource:(NSString*)source
                target:(NSString*)target
            completion:(FGTranslatorMultipleCompletionHandler)completion {
    if (!completion || !texts || texts.count == 0)
        return;
    
    if (self.translationServiceType == FGTranslatorServiceTypeUnknown)
    {
        NSError *error = [self errorWithCode:FGTranslatorErrorMissingCredentials
                                 description:@"missing Google or Bing credentials"];
        completion(error, nil, nil);
        return;
    }
    
    if (self.translatorState == FGTranslatorStateInProgress)
    {
        NSError *error = [self errorWithCode:FGTranslatorErrorTranslationInProgress description:@"translation already in progress"];
        completion(error, nil, nil);
        return;
    }
    else if (self.translatorState == FGTranslatorStateCompleted)
    {
        NSError *error = [self errorWithCode:FGTranslatorErrorAlreadyTranslated description:@"translation already completed"];
        completion(error, nil, nil);
        return;
    }
    else
    {
        self.translatorState = FGTranslatorStateInProgress;
    }
    
    NSMutableArray *cachedSources = [NSMutableArray arrayWithCapacity:texts.count];
    NSMutableArray *cachedTranslations = [NSMutableArray arrayWithCapacity:texts.count];
    NSMutableArray *textsToTranslate = [NSMutableArray array];
    
    for (NSString *text in texts) {
        // check cache for existing translation
        NSDictionary *cached = [[PINCache sharedCache] objectForKey:[self cacheKeyForText:text target:target]];
        if (cached)
        {
            NSString *cachedSource = [cached objectForKey:@"src"];
            NSString *cachedTranslation = [cached objectForKey:@"txt"];
            
            NSLog(@"FGTranslator: returning cached translation");
            
            [cachedSources addObject:cachedSource ?: [NSNull null]];
            [cachedTranslations addObject:cachedTranslation];
        } else {
            [cachedSources addObject:[NSNull null]];
            [cachedTranslations addObject:[NSNull null]];
            [textsToTranslate addObject:text];
        }
    }
    
    source = [self filteredLanguageCodeFromCode:source];
    if (!target)
        target = [self filteredLanguageCodeFromCode:[[NSLocale preferredLanguages] objectAtIndex:0]];
    
    if ([[source lowercaseString] isEqualToString:target])
        source = nil;
    
    if (self.preferSourceGuess && [self shouldGuessSourceWithText:[texts objectAtIndex:0]])
        source = nil;
    
    void (^translateCompletion)(NSArray<NSString *> *, NSArray<NSString *> *, NSError *) = ^(NSArray<NSString *> *translatedMessages, NSArray<NSString *> *detectedSources, NSError *error) {
        if (error) {
            completion(error, nil, nil);
            return;
        }
        
        for (NSInteger i = 0; i < translatedMessages.count; i++) {
            NSString *translated = translatedMessages[i];
            NSString *source = detectedSources[i];
            
            [self cacheText:textsToTranslate[i]
                 translated:translated
                     source:source
                     target:target];
        }
        
        NSMutableArray *translated = [NSMutableArray arrayWithArray:translatedMessages];
        NSMutableArray *detected = [NSMutableArray arrayWithArray:detectedSources];
        
        // merge translated text into cached array
        for (NSInteger i = 0; i < cachedTranslations.count; i++) {
            NSString *cached = [cachedTranslations objectAtIndex:i];
            if ([cached isKindOfClass:[NSNull class]]) {
                [cachedTranslations replaceObjectAtIndex:i withObject:[translated objectAtIndex:0]];
                [cachedSources replaceObjectAtIndex:i withObject:[detected objectAtIndex:0]];
                [translated removeObjectAtIndex:0];
                [detected removeObjectAtIndex:0];
                if (translated.count == 0) {
                    break;
                }
            }
        }
        completion(nil, cachedTranslations, cachedSources);
    };
    
    if (textsToTranslate.count == 0) {
        translateCompletion(@[], @[], nil);
        return;
    }
    
    switch (self.translationServiceType) {
        case FGTranslatorServiceTypeGoogle:
            self.operation = [FGTranslateRequest googleTranslateMessages:textsToTranslate
                                                              withSource:source
                                                                  target:target
                                                                     key:self.googleAPIKey
                                                               quotaUser:self.quotaUser
                                                                 referer:self.referer
                                                              completion:translateCompletion];
            break;
        case FGTranslatorServiceTypeMicrosoft:
            self.operation = [FGTranslateRequest bingTranslateMessages:textsToTranslate
                                                            withSource:source
                                                                target:target
                                                              clientId:self.azureClientId
                                                          clientSecret:self.azureClientSecret
                                                            completion:translateCompletion];
            break;
        default: {
            NSError *error = [self errorWithCode:FGTranslatorErrorMissingCredentials
                                     description:@"missing Google or Bing credentials"];
            completion(error, nil, nil);
            
            self.translatorState = FGTranslatorStateCompleted;
        }
            break;
    }
}

- (void)translateText:(NSString *)text
           withSource:(NSString *)source
               target:(NSString *)target
           completion:(FGTranslatorCompletionHandler)completion
{
    [self translateTexts:@[text]
              withSource:source
                  target:target
              completion:^(NSError *error, NSArray<NSString *> *translated, NSArray<NSString *> *sourceLanguage) {
                  completion(error, translated[0], sourceLanguage);
              }];
}

- (void)detectLanguage:(NSString *)text
            completion:(void (^)(NSError *error, NSString *detectedSource, float confidence))completion
{
    if (!completion || !text || text.length == 0)
        return;
    
    if (self.translationServiceType == FGTranslatorServiceTypeUnknown)
    {
        NSError *error = [self errorWithCode:FGTranslatorErrorMissingCredentials
                                 description:@"missing Google or Bing credentials"];
        completion(error, nil, 0);
        return;
    }
    
    if (self.translatorState == FGTranslatorStateInProgress)
    {
        NSError *error = [self errorWithCode:FGTranslatorErrorTranslationInProgress description:@"detection already in progress"];
        completion(error, nil, 0);
        return;
    }
    else if (self.translatorState == FGTranslatorStateCompleted)
    {
        NSError *error = [self errorWithCode:FGTranslatorErrorAlreadyTranslated description:@"detection already completed"];
        completion(error, nil, 0);
        return;
    }
    else
    {
        self.translatorState = FGTranslatorStateInProgress;
    }
    
    
    switch (self.translationServiceType) {
        case FGTranslatorServiceTypeGoogle: {
            self.operation = [FGTranslateRequest googleDetectLanguage:text
                                                                  key:self.googleAPIKey
                                                            quotaUser:self.quotaUser
                                                              referer:self.referer
                                                           completion:^(NSString *detectedSource, float confidence, NSError *error)
                              {
                                  if (error)
                                  {
                                      FGTranslatorError errorState = error.code == FGTranslationErrorBadRequest ? FGTranslatorErrorUnableToTranslate : FGTranslatorErrorNetworkError;
                                      
                                      NSError *fgError = [self errorWithCode:errorState description:nil];
                                      if (completion)
                                          completion(fgError, nil, 0);
                                  }
                                  else
                                  {
                                      completion(nil, detectedSource, confidence);
                                  }
                                  
                                  self.translatorState = FGTranslatorStateCompleted;
                              }];
        }
            break;
        case FGTranslatorServiceTypeMicrosoft: {
            self.operation = [FGTranslateRequest bingDetectLanguage:text
                                                           clientId:self.azureClientId
                                                       clientSecret:self.azureClientSecret
                                                         completion:^(NSString *detectedLanguage, float confidence, NSError *error)
                              {
                                  if (error)
                                  {
                                      FGTranslatorError errorState = error.code == FGTranslationErrorBadRequest ? FGTranslatorErrorUnableToTranslate : FGTranslatorErrorNetworkError;
                                      
                                      NSError *fgError = [self errorWithCode:errorState description:nil];
                                      if (completion)
                                          completion(fgError, nil, 0);
                                  }
                                  else
                                  {
                                      completion(nil, detectedLanguage, confidence);
                                  }
                                  
                                  self.translatorState = FGTranslatorStateCompleted;
                              }];
        }
        default: {
            NSError *error = [self errorWithCode:FGTranslatorErrorMissingCredentials
                                     description:@"missing Google or Bing credentials"];
            completion(error, nil, 0);
            
            self.translatorState = FGTranslatorStateCompleted;
        }
            break;
    }
}

- (void)supportedLanguages:(void (^)(NSError *error, NSArray *languageCodes))completion
{
    if (!completion)
        return;
    
    if (self.translationServiceType == FGTranslatorServiceTypeUnknown)
    {
        NSError *error = [self errorWithCode:FGTranslatorErrorMissingCredentials
                                 description:@"missing Google or Bing credentials"];
        completion(error, nil);
        return;
    }
    
    if (self.translatorState == FGTranslatorStateInProgress)
    {
        NSError *error = [self errorWithCode:FGTranslatorErrorTranslationInProgress description:@"detection already in progress"];
        completion(error, nil);
        return;
    }
    else if (self.translatorState == FGTranslatorStateCompleted)
    {
        NSError *error = [self errorWithCode:FGTranslatorErrorAlreadyTranslated description:@"detection already completed"];
        completion(error, nil);
        return;
    }
    else
    {
        self.translatorState = FGTranslatorStateInProgress;
    }
    
    switch (self.translationServiceType) {
        case FGTranslatorServiceTypeGoogle: {
            self.operation = [FGTranslateRequest googleSupportedLanguagesWithKey:self.googleAPIKey
                                                                       quotaUser:self.quotaUser
                                                                         referer:self.referer
                                                                      completion:^(NSArray *languageCodes, NSError *error)
                              {
                                  if (error)
                                  {
                                      FGTranslatorError errorState = error.code == FGTranslationErrorBadRequest ? FGTranslatorErrorUnableToTranslate : FGTranslatorErrorNetworkError;
                                      
                                      NSError *fgError = [self errorWithCode:errorState description:nil];
                                      if (completion)
                                          completion(fgError, nil);
                                  }
                                  else
                                  {
                                      completion(nil, languageCodes);
                                  }
                                  
                                  self.translatorState = FGTranslatorStateCompleted;
                              }];
        }
            break;
        case FGTranslatorServiceTypeMicrosoft: {
            self.operation = [FGTranslateRequest bingSupportedLanguagesWithClienId:self.azureClientId
                                                                      clientSecret:self.azureClientSecret
                                                                        completion:^(NSArray *languageCodes, NSError *error)
                              {
                                  if (error)
                                  {
                                      FGTranslatorError errorState = error.code == FGTranslationErrorBadRequest ? FGTranslatorErrorUnableToTranslate : FGTranslatorErrorNetworkError;
                                      
                                      NSError *fgError = [self errorWithCode:errorState description:nil];
                                      if (completion)
                                          completion(fgError, nil);
                                  }
                                  else
                                  {
                                      completion(nil, languageCodes);
                                  }
                                  
                                  self.translatorState = FGTranslatorStateCompleted;
                              }];
        }
            break;
        default: {
            NSError *error = [self errorWithCode:FGTranslatorErrorMissingCredentials
                                     description:@"missing Google or Bing credentials"];
            completion(error, nil);
            
            self.translatorState = FGTranslatorStateCompleted;
        }
            break;
    }
}

- (void)handleError:(NSError *)error
{
    FGTranslatorError errorState = error.code == FGTranslationErrorBadRequest ? FGTranslatorErrorUnableToTranslate : FGTranslatorErrorNetworkError;
    
    NSError *fgError = [self errorWithCode:errorState description:nil];
    if (self.completionHandler)
        self.completionHandler(fgError, nil, nil);
}

- (void)handleSuccessWithOriginal:(NSString *)original
                translatedMessage:(NSString *)translatedMessage
                   detectedSource:(NSString *)detectedSource
						   target:(NSString *)target
{
    self.completionHandler(nil, translatedMessage, detectedSource);
    [self cacheText:original translated:translatedMessage source:detectedSource target:target];
}

- (void)cancel
{
    self.completionHandler = nil;
    [self.operation cancel];
}


#pragma mark - Utils

- (FGTranslatorServiceType)translationServiceType {
    if (self.googleAPIKey.length) {
        return FGTranslatorServiceTypeGoogle;
    } else if (self.azureClientId.length && self.azureClientSecret.length) {
        return FGTranslatorServiceTypeMicrosoft;
    }
    return FGTranslatorServiceTypeUnknown;
}

- (BOOL)shouldGuessSourceWithText:(NSString *)text
{
    return [text wordCount] >= 5 && [text wordCharacterCount] >= 25;
}

- (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description
{
    NSDictionary *userInfo = nil;
    if (description)
        userInfo = [NSDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey];
    
    return [NSError errorWithDomain:FG_TRANSLATOR_ERROR_DOMAIN code:code userInfo:userInfo];
}

// massage languge code to make Google Translate happy
- (NSString *)filteredLanguageCodeFromCode:(NSString *)code
{
    if (!code || code.length <= 3)
        return code;
    
    if ([code isEqualToString:@"zh-Hant"] || [code isEqualToString:@"zh-TW"])
        return @"zh-TW";
    else if ([code hasSuffix:@"input"])
        // use phone's default language if crazy (keyboard) inputs are detected
        return [[NSLocale preferredLanguages] objectAtIndex:0];
    else
        // trim stuff like en-GB to just en which Google Translate understands
        return [code substringToIndex:2];
}

@end
