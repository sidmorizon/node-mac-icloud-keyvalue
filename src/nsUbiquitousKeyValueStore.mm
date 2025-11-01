#include <napi.h>

// Apple APIs
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CloudKit/CloudKit.h>

#include "json_formatter.h"

/* HELPER FUNCTIONS */

Napi::Array NSArrayToNapiArray(Napi::Env env, NSArray *array);
Napi::Object NSDictionaryToNapiObject(Napi::Env env, NSDictionary *dict);
NSArray *NapiArrayToNSArray(Napi::Array array);
NSDictionary *NapiObjectToNSDictionary(Napi::Object object);

// Converts a std::string to an NSString.
NSString *ToNSString(const std::string &str) {
  return [NSString stringWithUTF8String:str.c_str()];
}

// Returns the document directory path from NSFileManager.
Napi::String GetDocumentDirectoryPath(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSArray *paths = [fileManager URLsForDirectory:NSDocumentDirectory 
                                       inDomains:NSUserDomainMask];
  NSURL *documentsURL = [paths firstObject];
  NSString *path = [documentsURL path];
  return Napi::String::New(env, std::string([path UTF8String]));
}

// Returns the iCloud directory path from NSFileManager.
Napi::String GetiCloudDirectoryPath(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSURL *iCloudURL = [fileManager URLForUbiquityContainerIdentifier:nil];
  if (iCloudURL) {
    NSString *path = [iCloudURL path];
    return Napi::String::New(env, std::string([path UTF8String]));
  }
  return Napi::String::New(env, "");
}

// Converts a NSArray to a Napi::Array.
Napi::Array NSArrayToNapiArray(Napi::Env env, NSArray *array) {
  if (!array)
    return Napi::Array::New(env, 0);

  size_t length = [array count];
  Napi::Array result = Napi::Array::New(env, length);

  for (size_t idx = 0; idx < length; idx++) {
    id value = array[idx];
    if ([value isKindOfClass:[NSString class]]) {
      result[idx] = std::string([value UTF8String]);
    } else if ([value isKindOfClass:[NSNumber class]]) {
      const char *objc_type = [value objCType];
      if (strcmp(objc_type, @encode(BOOL)) == 0 ||
          strcmp(objc_type, @encode(char)) == 0) {
        result[idx] = [value boolValue];
      } else if (strcmp(objc_type, @encode(double)) == 0 ||
                 strcmp(objc_type, @encode(float)) == 0) {
        result[idx] = [value doubleValue];
      } else {
        result[idx] = [value intValue];
      }
    } else if ([value isKindOfClass:[NSArray class]]) {
      result[idx] = NSArrayToNapiArray(env, value);
    } else if ([value isKindOfClass:[NSDictionary class]]) {
      result[idx] = NSDictionaryToNapiObject(env, value);
    } else {
      result[idx] = std::string([[value description] UTF8String]);
    }
  }

  return result;
}

// Converts a Napi::Object to an NSDictionary.
NSDictionary *NapiObjectToNSDictionary(Napi::Value value) {
  std::string json;
  if (!JSONFormatter::Format(value, &json))
    return nil;

  NSData *jsonData = [NSData dataWithBytes:json.c_str() length:json.length()];
  id obj = [NSJSONSerialization JSONObjectWithData:jsonData
                                           options:0
                                             error:nil];

  return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

// Converts a Napi::Array to an NSArray.
NSArray *NapiArrayToNSArray(Napi::Array array) {
  NSMutableArray *mutable_array =
      [NSMutableArray arrayWithCapacity:array.Length()];

  for (size_t idx = 0; idx < array.Length(); idx++) {
    Napi::Value val = array[idx];

    if (val.IsNumber()) {
      NSNumber *wrappedInt = [NSNumber numberWithInt:val.ToNumber()];
      [mutable_array addObject:wrappedInt];
    } else if (val.IsBoolean()) {
      NSNumber *wrappedBool = [NSNumber numberWithBool:val.ToBoolean()];
      [mutable_array addObject:wrappedBool];
    } else if (val.IsString()) {
      const std::string str = (std::string)val.ToString();
      [mutable_array addObject:ToNSString(str)];
    } else if (val.IsArray()) {
      Napi::Array sub_array = val.As<Napi::Array>();

      if (NSArray *ns_arr = NapiArrayToNSArray(sub_array)) {
        [mutable_array addObject:ns_arr];
      }
    } else if (val.IsObject()) {
      if (NSDictionary *dict = NapiObjectToNSDictionary(val)) {
        [mutable_array addObject:dict];
      }
    }
  }

  return mutable_array;
}

// Converts an NSDictionary to a Napi::Object.
Napi::Object NSDictionaryToNapiObject(Napi::Env env, NSDictionary *dict) {
  Napi::Object result = Napi::Object::New(env);

  if (!dict) {
    return result;
  }

  for (id key in dict) {
    const std::string str_key =
        [key isKindOfClass:[NSString class]]
            ? std::string([key UTF8String])
            : std::string([[key description] UTF8String]);

    id value = [dict objectForKey:key];
    if ([value isKindOfClass:[NSString class]]) {
      result.Set(str_key, std::string([value UTF8String]));
    } else if ([value isKindOfClass:[NSNumber class]]) {
      const char *objc_type = [value objCType];

      if (
        strcmp(objc_type, @encode(BOOL)) == 0 ||
        strcmp(objc_type, @encode(char)) == 0
      ) {
        result.Set(str_key, [value boolValue]);
      } else if (
        strcmp(objc_type, @encode(double)) == 0 ||
        strcmp(objc_type, @encode(float)) == 0
      ) {
        result.Set(str_key, [value doubleValue]);
      } else {
        result.Set(str_key, [value intValue]);
      }
    } else if ([value isKindOfClass:[NSArray class]]) {
      result.Set(str_key, NSArrayToNapiArray(env, value));
    } else if ([value isKindOfClass:[NSDictionary class]]) {
      result.Set(str_key, NSDictionaryToNapiObject(env, value));
    } else {
      result.Set(str_key, std::string([[value description] UTF8String]));
    }
  }

  return result;
}

/* EXPORTED FUNCTIONS */

// Returns all NSUbiquitousKeyValueStore for the current user.
Napi::Object GetAllValues(const Napi::CallbackInfo &info) {
  NSUbiquitousKeyValueStore *defaults = [&]() {
    return [NSUbiquitousKeyValueStore defaultStore];
  }();

  NSDictionary *all_defaults = [defaults dictionaryRepresentation];
  return NSDictionaryToNapiObject(info.Env(), all_defaults);
}

// Returns the value of 'key' in NSUbiquitousKeyValueStore for a specified type.
Napi::Value GetValue(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  const std::string type = (std::string)info[0].ToString();
  const std::string key = (std::string)info[1].ToString();

  NSUbiquitousKeyValueStore *defaults = [&]() {
    return [NSUbiquitousKeyValueStore defaultStore];
  }();

  NSString *default_key = [NSString stringWithUTF8String:key.c_str()];

  if (type == "string") {
    NSString *s = [defaults stringForKey:default_key];
    return Napi::String::New(env, s ? std::string([s UTF8String]) : "");
  } else if (type == "boolean") {
    bool b = [defaults boolForKey:default_key];
    return Napi::Boolean::New(env, b ? b : false);
  } else if (type == "double") {
    float f = [defaults doubleForKey:default_key];
    return Napi::Number::New(env, f ? f : 0);
  } else if (type == "array") {
    NSArray *array = [defaults arrayForKey:default_key];
    return NSArrayToNapiArray(env, array);
  } else if (type == "dictionary") {
    NSDictionary *dict = [defaults dictionaryForKey:default_key];
    return NSDictionaryToNapiObject(env, dict);
  } else {
    return env.Null();
  }
}

// Sets the value for 'key' in NSUbiquitousKeyValueStore.
void SetValue(const Napi::CallbackInfo &info) {
  const std::string type = (std::string)info[0].ToString();
  const std::string key = (std::string)info[1].ToString();
  NSString *default_key = ToNSString(key);

  NSUbiquitousKeyValueStore *defaults = [&]() {
    return [NSUbiquitousKeyValueStore defaultStore];
  }();

  if (type == "string") {
    const std::string value = (std::string)info[2].ToString();
    [defaults setObject:ToNSString(value) forKey:default_key];
  } else if (type == "boolean") {
    bool value = info[2].ToBoolean();
    [defaults setBool:value forKey:default_key];
  } else if (type == "float" || type == "integer" || type == "double") {
    double value = info[2].ToNumber().DoubleValue();
    [defaults setDouble:value forKey:default_key];
  } else if (type == "array") {
    Napi::Array array = info[2].As<Napi::Array>();

    if (NSArray *ns_arr = NapiArrayToNSArray(array)) {
      [defaults setObject:ns_arr forKey:default_key];
    }
  } else if (type == "dictionary") {
    Napi::Value value = info[2].As<Napi::Value>();

    if (NSDictionary *dict = NapiObjectToNSDictionary(value)) {
      [defaults setObject:dict forKey:default_key];
    }
  }
}

// Removes the value for 'key' in NSUbiquitousKeyValueStore.
void RemoveValue(const Napi::CallbackInfo &info) {
  const std::string key = (std::string)info[0].ToString();
  NSString *default_key = ToNSString(key);

  NSUbiquitousKeyValueStore *defaults = [&]() {
    return [NSUbiquitousKeyValueStore defaultStore];
  }();

  [defaults removeObjectForKey:default_key];
}

// Initializes all functions exposed to JS.
Napi::Object Init(Napi::Env env, Napi::Object exports) {
  exports.Set(Napi::String::New(env, "getAllValues"),
              Napi::Function::New(env, GetAllValues));
  exports.Set(Napi::String::New(env, "getValue"),
              Napi::Function::New(env, GetValue));
  exports.Set(Napi::String::New(env, "setValue"),
              Napi::Function::New(env, SetValue));
  exports.Set(Napi::String::New(env, "removeValue"),
              Napi::Function::New(env, RemoveValue));
  exports.Set(Napi::String::New(env, "getDocumentDirectoryPath"),
              Napi::Function::New(env, GetDocumentDirectoryPath));
  exports.Set(Napi::String::New(env, "getiCloudDirectoryPath"),
              Napi::Function::New(env, GetiCloudDirectoryPath));
  
  // Keychain functions
  exports.Set(Napi::String::New(env, "keychainSetItem"),
              Napi::Function::New(env, [](const Napi::CallbackInfo &info) {
                Napi::Env env = info.Env();
                if (info.Length() < 1 || !info[0].IsObject()) {
                  Napi::TypeError::New(env, "Expected params object").ThrowAsJavaScriptException();
                  return;
                }

                Napi::Object params = info[0].As<Napi::Object>();
                std::string key = (std::string)params.Get("key").ToString();
                std::string value = (std::string)params.Get("value").ToString();

                bool enableSync = true;
                if (params.Has("enableSync") && params.Get("enableSync").IsBoolean()) {
                  enableSync = params.Get("enableSync").ToBoolean();
                }

                NSString *service = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
                NSString *nsKey = ToNSString(key);
                NSString *nsValue = ToNSString(value);
                NSData *valueData = [nsValue dataUsingEncoding:NSUTF8StringEncoding];

                // Delete existing (both local and synced)
                NSMutableDictionary *deleteQuery = [@{
                  (id)kSecClass: (id)kSecClassGenericPassword,
                  (id)kSecAttrService: service,
                  (id)kSecAttrAccount: nsKey,
                  (id)kSecAttrSynchronizable: (id)kSecAttrSynchronizableAny
                } mutableCopy];
                SecItemDelete((CFDictionaryRef)deleteQuery);

                // Add new item
                NSMutableDictionary *addQuery = [@{
                  (id)kSecClass: (id)kSecClassGenericPassword,
                  (id)kSecAttrService: service,
                  (id)kSecAttrAccount: nsKey,
                  (id)kSecValueData: valueData,
                  (id)kSecAttrAccessible: (id)kSecAttrAccessibleWhenUnlocked,
                  (id)kSecAttrSynchronizable: enableSync ? (id)kCFBooleanTrue : (id)kCFBooleanFalse
                } mutableCopy];

                if (params.Has("label") && params.Get("label").IsString()) {
                  std::string label = (std::string)params.Get("label").ToString();
                  addQuery[(id)kSecAttrLabel] = ToNSString(label);
                }
                if (params.Has("description") && params.Get("description").IsString()) {
                  std::string desc = (std::string)params.Get("description").ToString();
                  addQuery[(id)kSecAttrDescription] = ToNSString(desc);
                }

                OSStatus status = SecItemAdd((CFDictionaryRef)addQuery, nil);
                if (status != errSecSuccess) {
                  Napi::Error::New(env, "Keychain add failed: " + std::to_string((int)status)).ThrowAsJavaScriptException();
                }
              }));

  exports.Set(Napi::String::New(env, "keychainGetItem"),
              Napi::Function::New(env, [](const Napi::CallbackInfo &info) -> Napi::Value {
                Napi::Env env = info.Env();
                if (info.Length() < 1 || !info[0].IsObject()) {
                  return Napi::TypeError::New(env, "Expected params object").Value();
                }

                Napi::Object params = info[0].As<Napi::Object>();
                std::string key = (std::string)params.Get("key").ToString();

                NSString *service = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
                NSString *nsKey = ToNSString(key);

                NSDictionary *query = @{
                  (id)kSecClass: (id)kSecClassGenericPassword,
                  (id)kSecAttrService: service,
                  (id)kSecAttrAccount: nsKey,
                  (id)kSecReturnData: (id)kCFBooleanTrue,
                  (id)kSecMatchLimit: (id)kSecMatchLimitOne,
                  (id)kSecAttrSynchronizable: (id)kSecAttrSynchronizableAny
                };

                CFTypeRef result = NULL;
                OSStatus status = SecItemCopyMatching((CFDictionaryRef)query, &result);
                if (status == errSecSuccess) {
                  NSData *valueData = (__bridge_transfer NSData *)result;
                  NSString *value = [[NSString alloc] initWithData:valueData encoding:NSUTF8StringEncoding];
                  if (!value) {
                    return env.Null();
                  }
                  Napi::Object out = Napi::Object::New(env);
                  out.Set("key", key);
                  out.Set("value", std::string([value UTF8String]));
                  return out;
                } else if (status == errSecItemNotFound) {
                  return env.Null();
                } else {
                  Napi::Error::New(env, "Keychain get failed: " + std::to_string((int)status)).ThrowAsJavaScriptException();
                  return env.Null();
                }
              }));

  exports.Set(Napi::String::New(env, "keychainRemoveItem"),
              Napi::Function::New(env, [](const Napi::CallbackInfo &info) {
                Napi::Env env = info.Env();
                if (info.Length() < 1 || !info[0].IsObject()) {
                  Napi::TypeError::New(env, "Expected params object").ThrowAsJavaScriptException();
                  return;
                }

                Napi::Object params = info[0].As<Napi::Object>();
                std::string key = (std::string)params.Get("key").ToString();

                NSString *service = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
                NSString *nsKey = ToNSString(key);

                NSDictionary *query = @{
                  (id)kSecClass: (id)kSecClassGenericPassword,
                  (id)kSecAttrService: service,
                  (id)kSecAttrAccount: nsKey,
                  (id)kSecAttrSynchronizable: (id)kSecAttrSynchronizableAny
                };

                OSStatus status = SecItemDelete((CFDictionaryRef)query);
                if (!(status == errSecSuccess || status == errSecItemNotFound)) {
                  Napi::Error::New(env, "Keychain remove failed: " + std::to_string((int)status)).ThrowAsJavaScriptException();
                }
              }));

  exports.Set(Napi::String::New(env, "keychainHasItem"),
              Napi::Function::New(env, [](const Napi::CallbackInfo &info) -> Napi::Value {
                Napi::Env env = info.Env();
                if (info.Length() < 1 || !info[0].IsObject()) {
                  return Napi::TypeError::New(env, "Expected params object").Value();
                }

                Napi::Object params = info[0].As<Napi::Object>();
                std::string key = (std::string)params.Get("key").ToString();

                NSString *service = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
                NSString *nsKey = ToNSString(key);

                NSDictionary *query = @{
                  (id)kSecClass: (id)kSecClassGenericPassword,
                  (id)kSecAttrService: service,
                  (id)kSecAttrAccount: nsKey,
                  (id)kSecAttrSynchronizable: (id)kSecAttrSynchronizableAny
                };

                OSStatus status = SecItemCopyMatching((CFDictionaryRef)query, NULL);
                return Napi::Boolean::New(env, status == errSecSuccess);
              }));

  exports.Set(Napi::String::New(env, "keychainIsICloudSyncEnabled"),
              Napi::Function::New(env, [](const Napi::CallbackInfo &info) -> Napi::Value {
                Napi::Env env = info.Env();
                NSString *service = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
                NSString *testKey = @"__onekey_icloud_sync_test__";
                NSData *valueData = [@"test" dataUsingEncoding:NSUTF8StringEncoding];

                NSDictionary *deleteQuery = @{
                  (id)kSecClass: (id)kSecClassGenericPassword,
                  (id)kSecAttrService: service,
                  (id)kSecAttrAccount: testKey,
                  (id)kSecAttrSynchronizable: (id)kSecAttrSynchronizableAny
                };
                SecItemDelete((CFDictionaryRef)deleteQuery);

                NSDictionary *addQuery = @{
                  (id)kSecClass: (id)kSecClassGenericPassword,
                  (id)kSecAttrService: service,
                  (id)kSecAttrAccount: testKey,
                  (id)kSecValueData: valueData,
                  (id)kSecAttrAccessible: (id)kSecAttrAccessibleWhenUnlocked,
                  (id)kSecAttrSynchronizable: (id)kCFBooleanTrue
                };

                OSStatus status = SecItemAdd((CFDictionaryRef)addQuery, nil);
                SecItemDelete((CFDictionaryRef)deleteQuery);

                return Napi::Boolean::New(env, status == errSecSuccess);
              }));

  // CloudKit functions
  exports.Set(Napi::String::New(env, "cloudkitIsAvailable"),
              Napi::Function::New(env, [](const Napi::CallbackInfo &info) -> Napi::Value {
                Napi::Env env = info.Env();
                __block CKAccountStatus status = CKAccountStatusCouldNotDetermine;
                dispatch_semaphore_t sema = dispatch_semaphore_create(0);
                [[CKContainer defaultContainer] accountStatusWithCompletionHandler:^(CKAccountStatus s, NSError * _Nullable error) {
                  status = s;
                  dispatch_semaphore_signal(sema);
                }];
                dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
                return Napi::Boolean::New(env, status == CKAccountStatusAvailable);
              }));

  exports.Set(Napi::String::New(env, "cloudkitSaveRecord"),
              Napi::Function::New(env, [](const Napi::CallbackInfo &info) -> Napi::Value {
                Napi::Env env = info.Env();
                if (info.Length() < 1 || !info[0].IsObject()) {
                  return Napi::TypeError::New(env, "Expected params object").Value();
                }
                Napi::Object params = info[0].As<Napi::Object>();
                std::string recordTypeStr = (std::string)params.Get("recordType").ToString();
                std::string recordIDStr = (std::string)params.Get("recordID").ToString();
                std::string dataStr = (std::string)params.Get("data").ToString();

                CKContainer *container = [CKContainer defaultContainer];
                CKDatabase *db = [container privateCloudDatabase];
                CKRecordID *rid = [[CKRecordID alloc] initWithRecordName:ToNSString(recordIDStr)];
                CKRecord *rec = [[CKRecord alloc] initWithRecordType:ToNSString(recordTypeStr) recordID:rid];
                rec[@"data"] = ToNSString(dataStr);

                __block CKRecord *saved = nil;
                __block NSError *err = nil;
                dispatch_semaphore_t sema = dispatch_semaphore_create(0);
                [db saveRecord:rec completionHandler:^(CKRecord * _Nullable record, NSError * _Nullable error) {
                  saved = record;
                  err = error;
                  dispatch_semaphore_signal(sema);
                }];
                dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

                if (err) {
                  Napi::Error::New(env, std::string("CloudKit save failed: ") + [[err localizedDescription] UTF8String]).ThrowAsJavaScriptException();
                  return env.Null();
                }
                NSTimeInterval created = saved.creationDate ? [saved.creationDate timeIntervalSince1970] * 1000.0 : 0;
                Napi::Object out = Napi::Object::New(env);
                out.Set("recordID", std::string([saved.recordID.recordName UTF8String]));
                out.Set("createdAt", Napi::Number::New(env, created));
                return out;
              }));

  exports.Set(Napi::String::New(env, "cloudkitFetchRecord"),
              Napi::Function::New(env, [](const Napi::CallbackInfo &info) -> Napi::Value {
                Napi::Env env = info.Env();
                if (info.Length() < 1 || !info[0].IsObject()) {
                  return Napi::TypeError::New(env, "Expected params object").Value();
                }
                Napi::Object params = info[0].As<Napi::Object>();
                std::string recordTypeStr = (std::string)params.Get("recordType").ToString();
                std::string recordIDStr = (std::string)params.Get("recordID").ToString();

                CKContainer *container = [CKContainer defaultContainer];
                CKDatabase *db = [container privateCloudDatabase];
                CKRecordID *rid = [[CKRecordID alloc] initWithRecordName:ToNSString(recordIDStr)];

                __block CKRecord *fetched = nil;
                __block NSError *err = nil;
                dispatch_semaphore_t sema = dispatch_semaphore_create(0);
                [db fetchRecordWithID:rid completionHandler:^(CKRecord * _Nullable record, NSError * _Nullable error) {
                  fetched = record;
                  err = error;
                  dispatch_semaphore_signal(sema);
                }];
                dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

                if (err) {
                  if ([err.domain isEqualToString:CKErrorDomain] && err.code == CKErrorUnknownItem) {
                    return env.Null();
                  }
                  Napi::Error::New(env, std::string("CloudKit fetch failed: ") + [[err localizedDescription] UTF8String]).ThrowAsJavaScriptException();
                  return env.Null();
                }
                NSString *data = (NSString *)fetched[@"data"];
                NSTimeInterval created = fetched.creationDate ? [fetched.creationDate timeIntervalSince1970] * 1000.0 : 0;
                NSTimeInterval modified = fetched.modificationDate ? [fetched.modificationDate timeIntervalSince1970] * 1000.0 : 0;
                Napi::Object out = Napi::Object::New(env);
                out.Set("recordID", std::string([fetched.recordID.recordName UTF8String]));
                out.Set("recordType", std::string([fetched.recordType UTF8String]));
                out.Set("data", data ? std::string([data UTF8String]) : std::string(""));
                out.Set("createdAt", Napi::Number::New(env, created));
                out.Set("modifiedAt", Napi::Number::New(env, modified));
                return out;
              }));

  exports.Set(Napi::String::New(env, "cloudkitDeleteRecord"),
              Napi::Function::New(env, [](const Napi::CallbackInfo &info) {
                Napi::Env env = info.Env();
                if (info.Length() < 1 || !info[0].IsObject()) {
                  Napi::TypeError::New(env, "Expected params object").ThrowAsJavaScriptException();
                  return;
                }
                Napi::Object params = info[0].As<Napi::Object>();
                std::string recordIDStr = (std::string)params.Get("recordID").ToString();

                CKContainer *container = [CKContainer defaultContainer];
                CKDatabase *db = [container privateCloudDatabase];
                CKRecordID *rid = [[CKRecordID alloc] initWithRecordName:ToNSString(recordIDStr)];

                __block NSError *err = nil;
                dispatch_semaphore_t sema = dispatch_semaphore_create(0);
                [db deleteRecordWithID:rid completionHandler:^(CKRecordID * _Nullable recordID, NSError * _Nullable error) {
                  err = error;
                  dispatch_semaphore_signal(sema);
                }];
                dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

                if (err) {
                  if ([err.domain isEqualToString:CKErrorDomain] && err.code == CKErrorUnknownItem) {
                    return; // treat as success
                  }
                  Napi::Error::New(env, std::string("CloudKit delete failed: ") + [[err localizedDescription] UTF8String]).ThrowAsJavaScriptException();
                }
              }));

  exports.Set(Napi::String::New(env, "cloudkitRecordExists"),
              Napi::Function::New(env, [](const Napi::CallbackInfo &info) -> Napi::Value {
                Napi::Env env = info.Env();
                if (info.Length() < 1 || !info[0].IsObject()) {
                  return Napi::TypeError::New(env, "Expected params object").Value();
                }
                Napi::Object params = info[0].As<Napi::Object>();
                std::string recordIDStr = (std::string)params.Get("recordID").ToString();

                CKContainer *container = [CKContainer defaultContainer];
                CKDatabase *db = [container privateCloudDatabase];
                CKRecordID *rid = [[CKRecordID alloc] initWithRecordName:ToNSString(recordIDStr)];

                __block CKRecord *fetched = nil;
                __block NSError *err = nil;
                dispatch_semaphore_t sema = dispatch_semaphore_create(0);
                [db fetchRecordWithID:rid completionHandler:^(CKRecord * _Nullable record, NSError * _Nullable error) {
                  fetched = record;
                  err = error;
                  dispatch_semaphore_signal(sema);
                }];
                dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

                if (err) {
                  if ([err.domain isEqualToString:CKErrorDomain] && err.code == CKErrorUnknownItem) {
                    return Napi::Boolean::New(env, false);
                  }
                  Napi::Error::New(env, std::string("CloudKit exists check failed: ") + [[err localizedDescription] UTF8String]).ThrowAsJavaScriptException();
                  return Napi::Boolean::New(env, false);
                }
                return Napi::Boolean::New(env, fetched != nil);
              }));

  exports.Set(Napi::String::New(env, "cloudkitQueryRecords"),
              Napi::Function::New(env, [](const Napi::CallbackInfo &info) -> Napi::Value {
                Napi::Env env = info.Env();
                if (info.Length() < 1 || !info[0].IsObject()) {
                  return Napi::TypeError::New(env, "Expected params object").Value();
                }
                Napi::Object params = info[0].As<Napi::Object>();
                std::string recordTypeStr = (std::string)params.Get("recordType").ToString();

                CKContainer *container = [CKContainer defaultContainer];
                CKDatabase *db = [container privateCloudDatabase];
                NSPredicate *predicate = [NSPredicate predicateWithValue:YES];
                CKQuery *query = [[CKQuery alloc] initWithRecordType:ToNSString(recordTypeStr) predicate:predicate];

                __block NSArray<CKRecord *> *results = nil;
                __block NSError *err = nil;
                dispatch_semaphore_t sema = dispatch_semaphore_create(0);
                [db performQuery:query inZoneWithID:nil completionHandler:^(NSArray<CKRecord *> * _Nullable r, NSError * _Nullable error) {
                  results = r;
                  err = error;
                  dispatch_semaphore_signal(sema);
                }];
                dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

                if (err) {
                  Napi::Error::New(env, std::string("CloudKit query failed: ") + [[err localizedDescription] UTF8String]).ThrowAsJavaScriptException();
                  return env.Null();
                }
                Napi::Array arr = Napi::Array::New(env, results.count);
                NSUInteger idx = 0;
                for (CKRecord *rec in results) {
                  NSString *data = (NSString *)rec[@"data"];
                  NSTimeInterval created = rec.creationDate ? [rec.creationDate timeIntervalSince1970] * 1000.0 : 0;
                  NSTimeInterval modified = rec.modificationDate ? [rec.modificationDate timeIntervalSince1970] * 1000.0 : 0;
                  Napi::Object obj = Napi::Object::New(env);
                  obj.Set("recordID", std::string([rec.recordID.recordName UTF8String]));
                  obj.Set("recordType", std::string([rec.recordType UTF8String]));
                  obj.Set("data", data ? std::string([data UTF8String]) : std::string(""));
                  obj.Set("createdAt", Napi::Number::New(env, created));
                  obj.Set("modifiedAt", Napi::Number::New(env, modified));
                  arr[idx++] = obj;
                }
                Napi::Object out = Napi::Object::New(env);
                out.Set("records", arr);
                return out;
              }));
  return exports;
}

#if NODE_MAJOR_VERSION >= 10
NAN_MODULE_WORKER_ENABLED(NODE_GYP_MODULE_NAME, Init)
#else
NODE_API_MODULE(NODE_GYP_MODULE_NAME, Init)
#endif

