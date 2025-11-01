declare module 'node-mac-icloud-keyvalue' {
  type TypeMap = {
    string: string;
    double: number;
    boolean: boolean;
    array: unknown[];
    dictionary: Record<string, unknown>;
  };

  export function getAllValues(): Record<string, TypeMap[keyof TypeMap]>;

  export function getValue<T extends keyof TypeMap>(type: T, key: string): TypeMap[T];

  export function setValue<T extends keyof TypeMap>(type: T, key: string, value: TypeMap[T]);

  export function removeValue(key: string): void;

  export function getDocumentDirectoryPath(): string;

  export function getiCloudDirectoryPath(): string;

  // Keychain APIs
  export function keychainSetItem(params: {
    key: string;
    value: string;
    enableSync?: boolean;
    label?: string;
    description?: string;
  }): void;

  export function keychainGetItem(params: { key: string }): { key: string; value: string } | null;

  export function keychainRemoveItem(params: { key: string }): void;

  export function keychainHasItem(params: { key: string }): boolean;

  export function keychainIsICloudSyncEnabled(): boolean;

  // CloudKit types
  export type CloudKitSaveRecordParams = { recordType: string; recordID: string; data: string };
  export type CloudKitFetchRecordParams = { recordType: string; recordID: string };
  export type CloudKitDeleteRecordParams = { recordType: string; recordID: string };
  export type CloudKitRecordExistsParams = { recordType: string; recordID: string };
  export type CloudKitQueryRecordsParams = { recordType: string };

  export type CloudKitSaveRecordResult = { recordID: string; createdAt: number };
  export type CloudKitRecordResult = {
    recordID: string;
    recordType: string;
    data: string;
    createdAt: number;
    modifiedAt: number;
  };
  export type CloudKitQueryRecordsResult = { records: CloudKitRecordResult[] };

  // CloudKit APIs
  export function cloudkitIsAvailable(): boolean;
  export function cloudkitSaveRecord(params: CloudKitSaveRecordParams): CloudKitSaveRecordResult;
  export function cloudkitFetchRecord(params: CloudKitFetchRecordParams): CloudKitRecordResult | null;
  export function cloudkitDeleteRecord(params: CloudKitDeleteRecordParams): void;
  export function cloudkitRecordExists(params: CloudKitRecordExistsParams): boolean;
  export function cloudkitQueryRecords(params: CloudKitQueryRecordsParams): CloudKitQueryRecordsResult;
}
