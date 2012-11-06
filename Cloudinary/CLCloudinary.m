//
//  Cloudinary.m
//  Cloudinary
//
//  Copyright (c) 2012 Cloudinary Ltd. All rights reserved.
//

#import "CLCloudinary.h"
#import "Security/Security.h"
#import <CommonCrypto/CommonDigest.h>
#import "CLTransformation.h"
#import "NSString+URLEncoding.h"
#import "NSDictionary+Utilities.h"

NSString * const CL_VERSION = @"0.2.3";

NSString * const CL_SHARED_CDN = @"d3jpl91pxevbkh.cloudfront.net";

@implementation CLCloudinary
+ (NSString*) version
{
    return CL_VERSION;
}

- (CLCloudinary *)init
{
    if ( self = [super init] )
    {
        config = [NSMutableDictionary dictionary];
        char* url = getenv("CLOUDINARY_URL");
        if (url != nil)
        {
            [self parseUrl:[NSString stringWithCString:url encoding:NSASCIIStringEncoding]];
        }
    }
    return self;
}

- (CLCloudinary *)initWithUrl: (NSString*)url
{
    CLCloudinary* cloudinary = [self init];
    [cloudinary parseUrl:url];
    return cloudinary;
}

- (CLCloudinary *)initWithDictionary: (NSDictionary*)options
{
    if ( self = [super init] )
    {
        config = [NSMutableDictionary dictionaryWithDictionary:options];
    }
    return self;
}

- (void) parseUrl: (NSString*)url
{
    NSURL *uri = [NSURL URLWithString:url];
    [config setValue:[uri user] forKey:@"api_key"];
    [config setValue:[uri password] forKey:@"api_secret"];
    [config setValue:[uri host] forKey:@"cloud_name"];
    if ([[uri path] isEqualToString:@""])
    {
        [config setValue:[NSNumber numberWithBool:NO] forKey:@"private_cdn"];
    }
    else
    {
        [config setValue:[NSNumber numberWithBool:YES] forKey:@"private_cdn"];
        [config setValue:[[uri path] substringFromIndex:1] forKey:@"secure_distribution"];
    }
}

- (NSDictionary*) config
{
    return config;
}

- (NSString *) cloudinaryApiUrl: (NSString*) action options: (NSDictionary*) options
{
    NSString* upload_prefix = [self get:@"upload_prefix" options:options defaultValue: @"https://api.cloudinary.com"];
    NSString* cloud_name = [self get:@"cloud_name" options:options defaultValue: nil];
    if (cloud_name == nil) [NSException raise:@"CloudinaryError" format:@"Must supply cloud_name in tag or in configuration"];
    NSString* resource_type = [options valueForKey:@"resource_type" defaultValue:@"image"];
    NSArray* components = [NSArray arrayWithObjects:upload_prefix, @"v1_1", cloud_name, resource_type, action, nil];
    return [components componentsJoinedByString:@"/"];
}

#define RANDOM_BYTES_LEN 8
- (NSString *) randomPublicId
{
    NSMutableString     *hexString  = [NSMutableString stringWithCapacity:(RANDOM_BYTES_LEN * 2)];
    for (int i = 0; i < RANDOM_BYTES_LEN; ++i)
        [hexString appendString:[NSString stringWithFormat:@"%02x", arc4random() & 0xFF]];
    return [NSString stringWithString:hexString];
}

- (NSString *) signedPreloadedImage: (NSDictionary*) result
{
    NSMutableString     *identifier;
    [identifier appendString:[result valueForKey:@"resource_type"]];
    [identifier appendString:@"/upload/v"];
    [identifier appendString:[result valueForKey:@"version"]];
    [identifier appendString:@"/"];
    [identifier appendString:[result valueForKey:@"public_id"]];
    NSString *format = [result valueForKey:@"format"];
    if (format != nil) {
        [identifier appendString:@"."];
        [identifier appendString:format];
    }
    [identifier appendString:@"#"];
    [identifier appendString:[result valueForKey:@"signature"]];
    return [NSString stringWithString:identifier];
}


- (NSString *) apiSignRequest: (NSDictionary*) paramsToSign secret:(NSString*) apiSecret
{
    NSArray* paramNames = [paramsToSign allKeys];
    NSMutableArray *params = [NSMutableArray arrayWithCapacity:[paramsToSign count]];
    paramNames = [paramNames sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString* param in paramNames) {
        NSString* paramValue = [CLCloudinary asString:[paramsToSign valueForKey:param]];
        if ([paramValue length] == 0) continue;
        NSArray* encoded = [NSArray arrayWithObjects:param, paramValue, nil];
        [params addObject:[encoded componentsJoinedByString:@"="]];
    }
    NSString *toSign = [params componentsJoinedByString:@"&"];
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_CTX ctx;
    CC_SHA1_Init(&ctx);
    NSData *stringBytes = [toSign dataUsingEncoding: NSUTF8StringEncoding];
    CC_SHA1_Update(&ctx, [stringBytes bytes], [stringBytes length]);
    stringBytes = [apiSecret dataUsingEncoding: NSUTF8StringEncoding];
    CC_SHA1_Update(&ctx, [stringBytes bytes], [stringBytes length]);

    CC_SHA1_Final(digest, &ctx);
    NSMutableString     *hexString  = [NSMutableString stringWithCapacity:(CC_SHA1_DIGEST_LENGTH * 2)];
    
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; ++i)
        [hexString appendString:[NSString stringWithFormat:@"%02x", (unsigned)digest[i]]];
    return [NSString stringWithString:hexString];
}

- (NSString*) url:(NSString*) source
{
    return [self url:source options:[NSDictionary dictionary]];
}

- (id) get:(NSString*)key options:(NSDictionary*)options defaultValue:(id)defaultValue
{
    return [options valueForKey:key defaultValue:[config valueForKey:key defaultValue:defaultValue]];
    
}

- (NSString*) url:(NSString*) source options:(NSDictionary*) options
{
    NSString* cloudName = [self get:@"cloud_name" options:options defaultValue:nil];
    if ([cloudName length] == 0) {
        [NSException raise:@"CloudinaryError" format:@"Must supply cloud_name in tag or in configuration"];
    }

    NSString* type = [options valueForKey:@"type" defaultValue:@"upload"];
    NSString* resourceType = [options valueForKey:@"resource_type" defaultValue:@"image"];
    NSString* format = [options valueForKey:@"format"];
    NSNumber* secure = [self get:@"secure" options:options defaultValue:[NSNumber numberWithBool:NO]];
    NSNumber* privateCdn = [self get:@"private_cdn" options:options defaultValue:[NSNumber numberWithBool:NO]];
    NSNumber* cdnSubdomain = [self get:@"cdn_subdomain" options:options defaultValue:[NSNumber numberWithBool:NO]];
    NSString* secureDistribution = [self get:@"secure_distribution" options:options defaultValue:nil];
    NSString* cname = [self get:@"cname" options:options defaultValue:nil];
    NSString* version = [CLCloudinary asString:[options valueForKey:@"version" defaultValue:@""]];

    CLTransformation* transformation = [options valueForKey:@"transformation"];
    if (transformation == nil) transformation = [CLTransformation transformation];
    if ([type isEqualToString:@"fetch"] && [format length] > 0)
    {
        [transformation setFetchFormat:format];
        format = nil;
    }
    NSString* transformationStr = [transformation generate];
    
    if (source == nil) return nil;
    NSString* originalSource = source;
    
    if ([source rangeOfString:@"^https?:/.*" options:NSCaseInsensitiveSearch|NSRegularExpressionSearch].location != NSNotFound)
    {
        if ([type isEqualToString:@"upload"] || [type isEqualToString:@"asset"])
        {
            return originalSource;
        }
        source = [source smartEncodeUrl:NSUTF8StringEncoding];
    } else if (format != nil) {
        source = [NSString stringWithFormat:@"%@.%@", source, format];
    }
    if ([secure boolValue] && [secureDistribution length] == 0)
    {
        if ([privateCdn boolValue])
        {
            [NSException raise:@"CloudinaryError" format:@"secure_distribution not defined"];
        } else
        {
            secureDistribution = CL_SHARED_CDN;
        }
    }
    NSMutableString* prefix = [NSMutableString string];
    if ([secure boolValue]) {
        [prefix appendString:@"https://"];
        [prefix appendString:secureDistribution];
    }
    else
    {
        [prefix appendString:@"http://"];
        if ([cdnSubdomain boolValue])
        {
            [prefix appendFormat:@"a%d.", [self crc32:source] % 5 + 1];
        }
        if ([cname length] > 0)
        {
            [prefix appendString:cname];
        }
        else if ([privateCdn boolValue])
        {
            [prefix appendFormat:@"%@-res.cloudinary.com", cloudName];
        }
        else
        {
            [prefix appendString:@"res.cloudinary.com"];
        }
    }
    if (![privateCdn boolValue])
    {
        [prefix appendString:@"/"];
        [prefix appendString:cloudName];
    }
    if ([version length] > 0)
    {
        version = [NSString stringWithFormat:@"v%@", version];
    }
    NSString* url = [[NSArray arrayWithObjects:prefix, resourceType, type, transformationStr, version, source, nil] componentsJoinedByString:@"/"];    
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"([^:])\\/+"
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:&error];
    
    return [regex stringByReplacingMatchesInString:url
                  options:0
                  range:NSMakeRange(0, [url length])
                  withTemplate:@"$1/"];
 
}

- (NSString*) imageTag:(NSString*) source
{
    return [self imageTag:source options:[NSDictionary dictionary]];
}

- (NSString*) imageTag:(NSString*) source options:(NSDictionary*) options
{
    return [self imageTag:source options:options htmlOptions:[NSDictionary dictionary]];
}

- (NSString*) imageTag:(NSString*) source options:(NSDictionary*) _options htmlOptions:(NSDictionary*) htmlOptions
{
    NSMutableDictionary* options = [NSMutableDictionary dictionaryWithDictionary:_options];
    CLTransformation* transformation = [options objectForKey:@"transformation"];
    if (transformation == nil)
    {
        transformation = [CLTransformation transformation];
        [options setValue:transformation forKey:@"transformation"];
    }
    NSString* url = [self url:source options:options];
    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithDictionary:htmlOptions];
    if (transformation.htmlHeight != nil) [attributes setValue:transformation.htmlHeight forKey:@"height"];
    if (transformation.htmlWidth != nil) [attributes setValue:transformation.htmlWidth forKey:@"width"];
    NSMutableString* tag = [NSMutableString string];
    [tag appendString:@"<img src='"];
    [tag appendString:url];
    [tag appendString:@"'"];
    for (NSString* key in [attributes allKeys])
    {
        [tag appendFormat:@" %@='%@'", key, [attributes valueForKey:key], nil];
    }
    [tag appendString:@"/>"];
    return tag;
}


+ (NSArray*) asArray: (id) value
{
    if (value == nil) {
        return [NSArray array];
    } else if ([value isKindOfClass:[NSArray class]]) {
        return value;
    } else {
        return [NSArray arrayWithObject:value];
    }
}	

+ (NSString*) asString: (id) value
{
    if (value == nil) {
        return nil;
    } else if ([value isKindOfClass:[NSString class]]) {
        return value;
    } else if ([value isKindOfClass:[NSNumber class]]) {
        NSNumber* number = value;
        return [number stringValue];
    } else {
        [NSException raise:@"CloudinaryError" format:@"Expected NSString or NSNumber"];
        return nil;
    }
}

+ (NSNumber*) asBool: (id) value
{
    if (value == nil) {
        return nil;
    } else if ([value isKindOfClass:[NSString class]]) {
        return [NSNumber numberWithBool:[(NSString*) value isEqualToString:@"true"]];
    } else if ([value isKindOfClass:[NSNumber class]]) {
        return [NSNumber numberWithBool:[(NSNumber*)value integerValue] == 1];
    } else {
        [NSException raise:@"CloudinaryError" format:@"Expected NSString or NSNumber"];
        return nil;
    }
}

- (unsigned) crc32:(NSString*) str
{
    // http://kevin.vanzonneveld.net
    // +   original by: Webtoolkit.info (http://www.webtoolkit.info/)
    // +   improved by: T0bsn
    // +   improved by: http://stackoverflow.com/questions/2647935/javascript-crc32-function-and-php-crc32-not-matching
    NSString* table = @"00000000 77073096 EE0E612C 990951BA 076DC419 706AF48F E963A535 9E6495A3 0EDB8832 79DCB8A4 E0D5E91E 97D2D988 09B64C2B 7EB17CBD E7B82D07 90BF1D91 1DB71064 6AB020F2 F3B97148 84BE41DE 1ADAD47D 6DDDE4EB F4D4B551 83D385C7 136C9856 646BA8C0 FD62F97A 8A65C9EC 14015C4F 63066CD9 FA0F3D63 8D080DF5 3B6E20C8 4C69105E D56041E4 A2677172 3C03E4D1 4B04D447 D20D85FD A50AB56B 35B5A8FA 42B2986C DBBBC9D6 ACBCF940 32D86CE3 45DF5C75 DCD60DCF ABD13D59 26D930AC 51DE003A C8D75180 BFD06116 21B4F4B5 56B3C423 CFBA9599 B8BDA50F 2802B89E 5F058808 C60CD9B2 B10BE924 2F6F7C87 58684C11 C1611DAB B6662D3D 76DC4190 01DB7106 98D220BC EFD5102A 71B18589 06B6B51F 9FBFE4A5 E8B8D433 7807C9A2 0F00F934 9609A88E E10E9818 7F6A0DBB 086D3D2D 91646C97 E6635C01 6B6B51F4 1C6C6162 856530D8 F262004E 6C0695ED 1B01A57B 8208F4C1 F50FC457 65B0D9C6 12B7E950 8BBEB8EA FCB9887C 62DD1DDF 15DA2D49 8CD37CF3 FBD44C65 4DB26158 3AB551CE A3BC0074 D4BB30E2 4ADFA541 3DD895D7 A4D1C46D D3D6F4FB 4369E96A 346ED9FC AD678846 DA60B8D0 44042D73 33031DE5 AA0A4C5F DD0D7CC9 5005713C 270241AA BE0B1010 C90C2086 5768B525 206F85B3 B966D409 CE61E49F 5EDEF90E 29D9C998 B0D09822 C7D7A8B4 59B33D17 2EB40D81 B7BD5C3B C0BA6CAD EDB88320 9ABFB3B6 03B6E20C 74B1D29A EAD54739 9DD277AF 04DB2615 73DC1683 E3630B12 94643B84 0D6D6A3E 7A6A5AA8 E40ECF0B 9309FF9D 0A00AE27 7D079EB1 F00F9344 8708A3D2 1E01F268 6906C2FE F762575D 806567CB 196C3671 6E6B06E7 FED41B76 89D32BE0 10DA7A5A 67DD4ACC F9B9DF6F 8EBEEFF9 17B7BE43 60B08ED5 D6D6A3E8 A1D1937E 38D8C2C4 4FDFF252 D1BB67F1 A6BC5767 3FB506DD 48B2364B D80D2BDA AF0A1B4C 36034AF6 41047A60 DF60EFC3 A867DF55 316E8EEF 4669BE79 CB61B38C BC66831A 256FD2A0 5268E236 CC0C7795 BB0B4703 220216B9 5505262F C5BA3BBE B2BD0B28 2BB45A92 5CB36A04 C2D7FFA7 B5D0CF31 2CD99E8B 5BDEAE1D 9B64C2B0 EC63F226 756AA39C 026D930A 9C0906A9 EB0E363F 72076785 05005713 95BF4A82 E2B87A14 7BB12BAE 0CB61B38 92D28E9B E5D5BE0D 7CDCEFB7 0BDBDF21 86D3D2D4 F1D4E242 68DDB3F8 1FDA836E 81BE16CD F6B9265B 6FB077E1 18B74777 88085AE6 FF0F6A70 66063BCA 11010B5C 8F659EFF F862AE69 616BFFD3 166CCF45 A00AE278 D70DD2EE 4E048354 3903B3C2 A7672661 D06016F7 4969474D 3E6E77DB AED16A4A D9D65ADC 40DF0B66 37D83BF0 A9BCAE53 DEBB9EC5 47B2CF7F 30B5FFE9 BDBDF21C CABAC28A 53B39330 24B4A3A6 BAD03605 CDD70693 54DE5729 23D967BF B3667A2E C4614AB8 5D681B02 2A6F2B94 B40BBE37 C30C8EA1 5A05DF1B 2D02EF8D";
    
    int crc = 0;
    unsigned int x = 0;
    int y = 0;
    int iTop = [str length];
    crc = crc ^ (-1);
    for (int i = 0; i < iTop; i++) {
        char ch = [str characterAtIndex:i];
        y = (crc ^ ch) & 0xFF;
        NSString* tableEntry = [table substringWithRange: (NSRange){y*9, 8}];
        NSScanner *scan = [NSScanner scannerWithString:tableEntry];
        [scan scanHexInt:&x];
        crc = ((crc >> 8) & 0x00FFFFFF) ^ x;
    }
    
    return crc ^ (-1);
}


@end
