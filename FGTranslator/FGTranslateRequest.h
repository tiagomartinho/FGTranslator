//
//  FGTranslateRequest.h
//  FGTranslatorDemo
//
//  Created by George Polak on 8/12/14.
//  Copyright (c) 2014 George Polak. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AFNetworking.h"

extern NSString *const FG_TRANSLATOR_ERROR_DOMAIN;

typedef NSInteger FGTranslationError;
enum
{
    FGTranslationErrorNoToken = 0,
    FGTranslationErrorBadRequest = 1,
    FGTranslationErrorOther = 2
};


@interface FGTranslateRequest : NSObject

#pragma mark - Google

+ (AFHTTPRequestOperation *)googleTranslateMessages:(NSArray <NSString*> *)messages
                                         withSource:(NSString *)source
                                             target:(NSString *)target
                                                key:(NSString *)key
                                          quotaUser:(NSString *)quotaUser
                                            referer:(NSString*)referer
                                         completion:(void (^)(NSArray <NSString*> *translatedMessages,
                                                              NSArray <NSString*> *detectedSources,
                                                              NSError *error))completion;

+ (AFHTTPRequestOperation *)googleDetectLanguage:(NSString *)text
                                             key:(NSString *)key
                                       quotaUser:(NSString *)quotaUser
                                         referer:(NSString*)referer
                                      completion:(void (^)(NSString *detectedSource, float confidence, NSError *error))completion;

+ (AFHTTPRequestOperation *)googleSupportedLanguagesWithKey:(NSString *)key
                                                  quotaUser:(NSString *)quotaUser
                                                    referer:(NSString*)referer
                                                 completion:(void (^)(NSArray *languageCodes, NSError *error))completion;


#pragma mark - Bing

+ (AFHTTPRequestOperation *)bingTranslateMessages:(NSArray <NSString*> *)messages
                                       withSource:(NSString *)source
                                           target:(NSString *)target
                                         clientId:(NSString *)clientId
                                     clientSecret:(NSString *)clientSecret
                                       completion:(void (^)(NSArray <NSString*> *translatedMessage, NSArray <NSString*> *detectedSource, NSError *error))completion;

+ (AFHTTPRequestOperation *)bingDetectLanguage:(NSString *)message
                                      clientId:(NSString *)clientId
                                  clientSecret:(NSString *)clientSecret
                                    completion:(void (^)(NSString *detectedLanguage, float confidence, NSError *error))completion;

+ (AFHTTPRequestOperation *)bingSupportedLanguagesWithClienId:(NSString *)clientId
                                                 clientSecret:(NSString *)clientSecret
                                                   completion:(void (^)(NSArray *languageCodes, NSError *error))completion;

#pragma mark - Misc

+ (void)flushCredentials;

@end
