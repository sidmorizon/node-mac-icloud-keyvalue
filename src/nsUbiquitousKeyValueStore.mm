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

// Base worker that resolves/rejects a Promise without blocking JS thread
class PromiseWorker : public Napi::AsyncWorker {
public:
  explicit PromiseWorker(Napi::Env env)
    : Napi::AsyncWorker(env), deferred(Napi::Promise::Deferred::New(env)) {}

  Napi::Promise GetPromise() { return deferred.Promise(); }

protected:
  Napi::Promise::Deferred deferred;
  void OnError(const Napi::Error &e) override {
    deferred.Reject(e.Value());
  }
};

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
              Napi::Function::New(env, [](const Napi::CallbackInfo &info) -> Napi::Value {
                Napi::Env env = info.Env();
                if (info.Length() < 1 || !info[0].IsObject()) {
                  Napi::TypeError::New(env, "Expected params object").ThrowAsJavaScriptException();
                  return env.Undefined();
                }
                Napi::Object params = info[0].As<Napi::Object>();
                std::string key = (std::string)params.Get("key").ToString();
                std::string value = (std::string)params.Get("value").ToString();
                bool enableSync = true;
                if (params.Has("enableSync") && params.Get("enableSync").IsBoolean()) {
                  enableSync = params.Get("enableSync").ToBoolean();
                }
                bool hasLabel = params.Has("label") && params.Get("label").IsString();
                std::string label = hasLabel ? (std::string)params.Get("label").ToString() : std::string();
                bool hasDesc = params.Has("description") && params.Get("description").IsString();
                std::string desc = hasDesc ? (std::string)params.Get("description").ToString() : std::string();

                class Worker : public PromiseWorker {
                 public:
                  Worker(Napi::Env env,
                         std::string key,
                         std::string value,
                         bool enableSync,
                         bool hasLabel,
                         std::string label,
                         bool hasDesc,
                         std::string desc)
                    : PromiseWorker(env), key_(std::move(key)), value_(std::move(value)), enableSync_(enableSync), hasLabel_(hasLabel), label_(std::move(label)), hasDesc_(hasDesc), desc_(std::move(desc)) {}

                  void Execute() override {
                    @autoreleasepool {
                      NSString *service = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
                      NSString *nsKey = ToNSString(key_);
                      NSString *nsValue = ToNSString(value_);
                      NSData *valueData = [nsValue dataUsingEncoding:NSUTF8StringEncoding];
                      NSMutableDictionary *deleteQuery = [@{
                        (id)kSecClass: (id)kSecClassGenericPassword,
                        (id)kSecAttrService: service,
                        (id)kSecAttrAccount: nsKey,
                        (id)kSecAttrSynchronizable: (id)kSecAttrSynchronizableAny
                      } mutableCopy];
                      SecItemDelete((CFDictionaryRef)deleteQuery);
                      NSMutableDictionary *addQuery = [@{
                        (id)kSecClass: (id)kSecClassGenericPassword,
                        (id)kSecAttrService: service,
                        (id)kSecAttrAccount: nsKey,
                        (id)kSecValueData: valueData,
                        (id)kSecAttrAccessible: (id)kSecAttrAccessibleWhenUnlocked,
                        (id)kSecAttrSynchronizable: enableSync_ ? (id)kCFBooleanTrue : (id)kCFBooleanFalse
                      } mutableCopy];
                      if (hasLabel_) {
                        addQuery[(id)kSecAttrLabel] = ToNSString(label_);
                      }
                      if (hasDesc_) {
                        addQuery[(id)kSecAttrDescription] = ToNSString(desc_);
                      }
                      OSStatus status = SecItemAdd((CFDictionaryRef)addQuery, nil);
                      if (status != errSecSuccess) {
                        this->SetError(std::string("Keychain add failed: ") + std::to_string((int)status));
                      }
                    }
                  }

                  void OnOK() override {
                    deferred.Resolve(Env().Undefined());
                  }

                 private:
                  std::string key_;
                  std::string value_;
                  bool enableSync_;
                  bool hasLabel_;
                  std::string label_;
                  bool hasDesc_;
                  std::string desc_;
                };

                auto *worker = new Worker(env, key, value, enableSync, hasLabel, label, hasDesc, desc);
                Napi::Promise promise = worker->GetPromise();
                worker->Queue();
                return promise;
              }));

  exports.Set(Napi::String::New(env, "keychainGetItem"),
              Napi::Function::New(env, [](const Napi::CallbackInfo &info) -> Napi::Value {
                Napi::Env env = info.Env();
                if (info.Length() < 1 || !info[0].IsObject()) {
                  Napi::TypeError::New(env, "Expected params object").ThrowAsJavaScriptException();
                  return env.Undefined();
                }
                Napi::Object params = info[0].As<Napi::Object>();
                std::string key = (std::string)params.Get("key").ToString();

                class Worker : public PromiseWorker {
                 public:
                  Worker(Napi::Env env, std::string key)
                    : PromiseWorker(env), key_(std::move(key)) {}

                  void Execute() override {
                    @autoreleasepool {
                      NSString *service = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
                      NSString *nsKey = ToNSString(key_);
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
                        if (value) {
                          value_ = std::string([value UTF8String]);
                          found_ = true;
                        }
                      } else if (status == errSecItemNotFound) {
                        found_ = false;
                      } else {
                        this->SetError(std::string("Keychain get failed: ") + std::to_string((int)status));
                      }
                    }
                  }

                  void OnOK() override {
                    Napi::Env env = Env();
                    if (!found_) {
                      deferred.Resolve(env.Null());
                      return;
                    }
                    Napi::Object out = Napi::Object::New(env);
                    out.Set("key", key_);
                    out.Set("value", value_);
                    deferred.Resolve(out);
                  }

                 private:
                  std::string key_;
                  std::string value_;
                  bool found_ = false;
                };

                auto *worker = new Worker(env, key);
                Napi::Promise promise = worker->GetPromise();
                worker->Queue();
                return promise;
              }));

  exports.Set(Napi::String::New(env, "keychainRemoveItem"),
              Napi::Function::New(env, [](const Napi::CallbackInfo &info) -> Napi::Value {
                Napi::Env env = info.Env();
                if (info.Length() < 1 || !info[0].IsObject()) {
                  Napi::TypeError::New(env, "Expected params object").ThrowAsJavaScriptException();
                  return env.Undefined();
                }
                Napi::Object params = info[0].As<Napi::Object>();
                std::string key = (std::string)params.Get("key").ToString();

                class Worker : public PromiseWorker {
                 public:
                  Worker(Napi::Env env, std::string key)
                    : PromiseWorker(env), key_(std::move(key)) {}
                  void Execute() override {
                    @autoreleasepool {
                      NSString *service = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
                      NSString *nsKey = ToNSString(key_);
                      NSDictionary *query = @{
                        (id)kSecClass: (id)kSecClassGenericPassword,
                        (id)kSecAttrService: service,
                        (id)kSecAttrAccount: nsKey,
                        (id)kSecAttrSynchronizable: (id)kSecAttrSynchronizableAny
                      };
                      OSStatus status = SecItemDelete((CFDictionaryRef)query);
                      if (!(status == errSecSuccess || status == errSecItemNotFound)) {
                        this->SetError(std::string("Keychain remove failed: ") + std::to_string((int)status));
                      }
                    }
                  }
                  void OnOK() override {
                    deferred.Resolve(Env().Undefined());
                  }
                 private:
                  std::string key_;
                };

                auto *worker = new Worker(env, key);
                Napi::Promise promise = worker->GetPromise();
                worker->Queue();
                return promise;
              }));

  exports.Set(Napi::String::New(env, "keychainHasItem"),
              Napi::Function::New(env, [](const Napi::CallbackInfo &info) -> Napi::Value {
                Napi::Env env = info.Env();
                if (info.Length() < 1 || !info[0].IsObject()) {
                  Napi::TypeError::New(env, "Expected params object").ThrowAsJavaScriptException();
                  return env.Undefined();
                }
                Napi::Object params = info[0].As<Napi::Object>();
                std::string key = (std::string)params.Get("key").ToString();

                class Worker : public PromiseWorker {
                 public:
                  Worker(Napi::Env env, std::string key)
                    : PromiseWorker(env), key_(std::move(key)) {}
                  void Execute() override {
                    @autoreleasepool {
                      NSString *service = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
                      NSString *nsKey = ToNSString(key_);
                      NSDictionary *query = @{
                        (id)kSecClass: (id)kSecClassGenericPassword,
                        (id)kSecAttrService: service,
                        (id)kSecAttrAccount: nsKey,
                        (id)kSecAttrSynchronizable: (id)kSecAttrSynchronizableAny
                      };
                      OSStatus status = SecItemCopyMatching((CFDictionaryRef)query, NULL);
                      has_ = (status == errSecSuccess);
                    }
                  }
                  void OnOK() override {
                    deferred.Resolve(Napi::Boolean::New(Env(), has_));
                  }
                 private:
                  std::string key_;
                  bool has_ = false;
                };

                auto *worker = new Worker(env, key);
                Napi::Promise promise = worker->GetPromise();
                worker->Queue();
                return promise;
              }));

  exports.Set(Napi::String::New(env, "keychainIsICloudSyncEnabled"),
              Napi::Function::New(env, [](const Napi::CallbackInfo &info) -> Napi::Value {
                Napi::Env env = info.Env();

                class Worker : public PromiseWorker {
                 public:
                  using PromiseWorker::PromiseWorker;
                  void Execute() override {
                    @autoreleasepool {
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
                      enabled_ = (status == errSecSuccess);
                    }
                  }
                  void OnOK() override {
                    deferred.Resolve(Napi::Boolean::New(Env(), enabled_));
                  }
                 private:
                  bool enabled_ = false;
                };

                auto *worker = new Worker(env);
                Napi::Promise promise = worker->GetPromise();
                worker->Queue();
                return promise;
              }));

  // CloudKit functions
  exports.Set(Napi::String::New(env, "cloudkitIsAvailable"),
              Napi::Function::New(env, [](const Napi::CallbackInfo &info) -> Napi::Value {
                Napi::Env env = info.Env();
                class Worker : public PromiseWorker {
                 public:
                  using PromiseWorker::PromiseWorker;
                  void Execute() override {
                    @autoreleasepool {
                      __block CKAccountStatus status = CKAccountStatusCouldNotDetermine;
                      dispatch_semaphore_t sema = dispatch_semaphore_create(0);
                      [[CKContainer defaultContainer] accountStatusWithCompletionHandler:^(CKAccountStatus s, NSError * _Nullable error) {
                        status = s;
                        dispatch_semaphore_signal(sema);
                      }];
                      dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
                      available_ = (status == CKAccountStatusAvailable);
                    }
                  }
                  void OnOK() override {
                    deferred.Resolve(Napi::Boolean::New(Env(), available_));
                  }
                 private:
                  bool available_ = false;
                };
                auto *worker = new Worker(env);
                Napi::Promise promise = worker->GetPromise();
                worker->Queue();
                return promise;
              }));

  exports.Set(Napi::String::New(env, "cloudkitSaveRecord"),
              Napi::Function::New(env, [](const Napi::CallbackInfo &info) -> Napi::Value {
                Napi::Env env = info.Env();
                if (info.Length() < 1 || !info[0].IsObject()) {
                  Napi::TypeError::New(env, "Expected params object").ThrowAsJavaScriptException();
                  return env.Undefined();
                }
                Napi::Object params = info[0].As<Napi::Object>();
                std::string recordTypeStr = (std::string)params.Get("recordType").ToString();
                std::string recordIDStr = (std::string)params.Get("recordID").ToString();
                std::string dataStr = (std::string)params.Get("data").ToString();

                class Worker : public PromiseWorker {
                 public:
                  Worker(Napi::Env env, std::string rt, std::string rid, std::string data)
                    : PromiseWorker(env), recordType_(std::move(rt)), recordID_(std::move(rid)), data_(std::move(data)) {}
                  void Execute() override {
                    @autoreleasepool {
                      CKContainer *container = [CKContainer defaultContainer];
                      CKDatabase *db = [container privateCloudDatabase];
                      CKRecordID *rid = [[CKRecordID alloc] initWithRecordName:ToNSString(recordID_)];
                      CKRecord *rec = [[CKRecord alloc] initWithRecordType:ToNSString(recordType_) recordID:rid];
                      rec[@"data"] = ToNSString(data_);
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
                        this->SetError(std::string("CloudKit save failed: ") + [[err localizedDescription] UTF8String]);
                        return;
                      }
                      createdAtMs_ = saved.creationDate ? [saved.creationDate timeIntervalSince1970] * 1000.0 : 0;
                      savedRecordId_ = std::string([saved.recordID.recordName UTF8String]);
                    }
                  }
                  void OnOK() override {
                    Napi::Object out = Napi::Object::New(Env());
                    out.Set("recordID", savedRecordId_);
                    out.Set("createdAt", Napi::Number::New(Env(), createdAtMs_));
                    deferred.Resolve(out);
                  }
                 private:
                  std::string recordType_;
                  std::string recordID_;
                  std::string data_;
                  std::string savedRecordId_;
                  double createdAtMs_ = 0;
                };

                auto *worker = new Worker(env, recordTypeStr, recordIDStr, dataStr);
                Napi::Promise promise = worker->GetPromise();
                worker->Queue();
                return promise;
              }));

  exports.Set(Napi::String::New(env, "cloudkitFetchRecord"),
              Napi::Function::New(env, [](const Napi::CallbackInfo &info) -> Napi::Value {
                Napi::Env env = info.Env();
                if (info.Length() < 1 || !info[0].IsObject()) {
                  Napi::TypeError::New(env, "Expected params object").ThrowAsJavaScriptException();
                  return env.Undefined();
                }
                Napi::Object params = info[0].As<Napi::Object>();
                std::string recordTypeStr = (std::string)params.Get("recordType").ToString();
                std::string recordIDStr = (std::string)params.Get("recordID").ToString();

                class Worker : public PromiseWorker {
                 public:
                  Worker(Napi::Env env, std::string rt, std::string rid)
                    : PromiseWorker(env), recordType_(std::move(rt)), recordID_(std::move(rid)) {}
                  void Execute() override {
                    @autoreleasepool {
                      CKContainer *container = [CKContainer defaultContainer];
                      CKDatabase *db = [container privateCloudDatabase];
                      CKRecordID *rid = [[CKRecordID alloc] initWithRecordName:ToNSString(recordID_)];
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
                          found_ = false;
                          return;
                        }
                        this->SetError(std::string("CloudKit fetch failed: ") + [[err localizedDescription] UTF8String]);
                        return;
                      }
                      found_ = true;
                      data_ = std::string([((NSString *)fetched[@"data"]) UTF8String] ?: "");
                      createdAtMs_ = fetched.creationDate ? [fetched.creationDate timeIntervalSince1970] * 1000.0 : 0;
                      modifiedAtMs_ = fetched.modificationDate ? [fetched.modificationDate timeIntervalSince1970] * 1000.0 : 0;
                      recordTypeOut_ = std::string([fetched.recordType UTF8String]);
                      recordIdOut_ = std::string([fetched.recordID.recordName UTF8String]);
                    }
                  }
                  void OnOK() override {
                    Napi::Env env = Env();
                    if (!found_) {
                      deferred.Resolve(env.Null());
                      return;
                    }
                    Napi::Object out = Napi::Object::New(env);
                    out.Set("recordID", recordIdOut_);
                    out.Set("recordType", recordTypeOut_);
                    out.Set("data", data_);
                    out.Set("createdAt", Napi::Number::New(env, createdAtMs_));
                    out.Set("modifiedAt", Napi::Number::New(env, modifiedAtMs_));
                    deferred.Resolve(out);
                  }
                 private:
                  std::string recordType_;
                  std::string recordID_;
                  bool found_ = false;
                  std::string recordIdOut_;
                  std::string recordTypeOut_;
                  std::string data_;
                  double createdAtMs_ = 0;
                  double modifiedAtMs_ = 0;
                };
                auto *worker = new Worker(env, recordTypeStr, recordIDStr);
                Napi::Promise promise = worker->GetPromise();
                worker->Queue();
                return promise;
              }));

  exports.Set(Napi::String::New(env, "cloudkitDeleteRecord"),
              Napi::Function::New(env, [](const Napi::CallbackInfo &info) -> Napi::Value {
                Napi::Env env = info.Env();
                if (info.Length() < 1 || !info[0].IsObject()) {
                  Napi::TypeError::New(env, "Expected params object").ThrowAsJavaScriptException();
                  return env.Undefined();
                }
                Napi::Object params = info[0].As<Napi::Object>();
                std::string recordIDStr = (std::string)params.Get("recordID").ToString();

                class Worker : public PromiseWorker {
                 public:
                  Worker(Napi::Env env, std::string rid)
                    : PromiseWorker(env), recordID_(std::move(rid)) {}
                  void Execute() override {
                    @autoreleasepool {
                      CKContainer *container = [CKContainer defaultContainer];
                      CKDatabase *db = [container privateCloudDatabase];
                      CKRecordID *rid = [[CKRecordID alloc] initWithRecordName:ToNSString(recordID_)];
                      __block NSError *err = nil;
                      dispatch_semaphore_t sema = dispatch_semaphore_create(0);
                      [db deleteRecordWithID:rid completionHandler:^(CKRecordID * _Nullable recordID, NSError * _Nullable error) {
                        err = error;
                        dispatch_semaphore_signal(sema);
                      }];
                      dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
                      if (err && !([err.domain isEqualToString:CKErrorDomain] && err.code == CKErrorUnknownItem)) {
                        this->SetError(std::string("CloudKit delete failed: ") + [[err localizedDescription] UTF8String]);
                      }
                    }
                  }
                  void OnOK() override { deferred.Resolve(Env().Undefined()); }
                 private:
                  std::string recordID_;
                };
                auto *worker = new Worker(env, recordIDStr);
                Napi::Promise promise = worker->GetPromise();
                worker->Queue();
                return promise;
              }));

  exports.Set(Napi::String::New(env, "cloudkitRecordExists"),
              Napi::Function::New(env, [](const Napi::CallbackInfo &info) -> Napi::Value {
                Napi::Env env = info.Env();
                if (info.Length() < 1 || !info[0].IsObject()) {
                  Napi::TypeError::New(env, "Expected params object").ThrowAsJavaScriptException();
                  return env.Undefined();
                }
                Napi::Object params = info[0].As<Napi::Object>();
                std::string recordIDStr = (std::string)params.Get("recordID").ToString();

                class Worker : public PromiseWorker {
                 public:
                  Worker(Napi::Env env, std::string rid)
                    : PromiseWorker(env), recordID_(std::move(rid)) {}
                  void Execute() override {
                    @autoreleasepool {
                      CKContainer *container = [CKContainer defaultContainer];
                      CKDatabase *db = [container privateCloudDatabase];
                      CKRecordID *rid = [[CKRecordID alloc] initWithRecordName:ToNSString(recordID_)];
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
                          exists_ = false;
                          return;
                        }
                        this->SetError(std::string("CloudKit exists check failed: ") + [[err localizedDescription] UTF8String]);
                        return;
                      }
                      exists_ = (fetched != nil);
                    }
                  }
                  void OnOK() override { deferred.Resolve(Napi::Boolean::New(Env(), exists_)); }
                 private:
                  std::string recordID_;
                  bool exists_ = false;
                };
                auto *worker = new Worker(env, recordIDStr);
                Napi::Promise promise = worker->GetPromise();
                worker->Queue();
                return promise;
              }));

  exports.Set(Napi::String::New(env, "cloudkitQueryRecords"),
              Napi::Function::New(env, [](const Napi::CallbackInfo &info) -> Napi::Value {
                Napi::Env env = info.Env();
                if (info.Length() < 1 || !info[0].IsObject()) {
                  Napi::TypeError::New(env, "Expected params object").ThrowAsJavaScriptException();
                  return env.Undefined();
                }
                Napi::Object params = info[0].As<Napi::Object>();
                std::string recordTypeStr = (std::string)params.Get("recordType").ToString();

                class Worker : public PromiseWorker {
                 public:
                  Worker(Napi::Env env, std::string rt)
                    : PromiseWorker(env), recordType_(std::move(rt)) {}
                  void Execute() override {
                    @autoreleasepool {
                      CKContainer *container = [CKContainer defaultContainer];
                      CKDatabase *db = [container privateCloudDatabase];
                      NSPredicate *predicate = [NSPredicate predicateWithValue:YES];
                      CKQuery *query = [[CKQuery alloc] initWithRecordType:ToNSString(recordType_) predicate:predicate];
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
                        this->SetError(std::string("CloudKit query failed: ") + [[err localizedDescription] UTF8String]);
                        return;
                      }
                      for (CKRecord *rec in results) {
                        Record out;
                        out.recordID = std::string([rec.recordID.recordName UTF8String]);
                        out.recordType = std::string([rec.recordType UTF8String]);
                        NSString *data = (NSString *)rec[@"data"];
                        out.data = data ? std::string([data UTF8String]) : std::string("");
                        out.createdAt = rec.creationDate ? [rec.creationDate timeIntervalSince1970] * 1000.0 : 0;
                        out.modifiedAt = rec.modificationDate ? [rec.modificationDate timeIntervalSince1970] * 1000.0 : 0;
                        records_.push_back(std::move(out));
                      }
                    }
                  }
                  void OnOK() override {
                    Napi::Env env = Env();
                    Napi::Array arr = Napi::Array::New(env, records_.size());
                    for (size_t i = 0; i < records_.size(); ++i) {
                      const auto &r = records_[i];
                      Napi::Object obj = Napi::Object::New(env);
                      obj.Set("recordID", r.recordID);
                      obj.Set("recordType", r.recordType);
                      obj.Set("data", r.data);
                      obj.Set("createdAt", Napi::Number::New(env, r.createdAt));
                      obj.Set("modifiedAt", Napi::Number::New(env, r.modifiedAt));
                      arr[(uint32_t)i] = obj;
                    }
                    Napi::Object out = Napi::Object::New(env);
                    out.Set("records", arr);
                    deferred.Resolve(out);
                  }
                 private:
                  struct Record { std::string recordID; std::string recordType; std::string data; double createdAt; double modifiedAt; };
                  std::string recordType_;
                  std::vector<Record> records_;
                };
                auto *worker = new Worker(env, recordTypeStr);
                Napi::Promise promise = worker->GetPromise();
                worker->Queue();
                return promise;
              }));
  return exports;
}

#if NODE_MAJOR_VERSION >= 10
NAN_MODULE_WORKER_ENABLED(NODE_GYP_MODULE_NAME, Init)
#else
NODE_API_MODULE(NODE_GYP_MODULE_NAME, Init)
#endif

