const nsUbiquitousKeyValueStore = require('bindings')('nsUbiquitousKeyValueStore.node');

const VALID_TYPES = ['string', 'double', 'boolean', 'array', 'dictionary'];

function getAllValues() {
  return nsUbiquitousKeyValueStore.getAllValues.call(this);
}

function getValue(type, key) {
  if (!VALID_TYPES.includes(type)) {
    throw new TypeError(`${type} must be one of ${VALID_TYPES.join(', ')}`);
  }

  return nsUbiquitousKeyValueStore.getValue.call(this, type, key);
}

function setValue(type, key, value) {
  if (!VALID_TYPES.includes(type)) {
    throw new TypeError(`${type} must be one of ${VALID_TYPES.join(', ')}`);
  }

  const isFloatOrDouble = (n) => !isNaN(parseFloat(n));
  const isObject = (o) => Object.prototype.toString.call(o) === '[object Object]';

  if (type === 'string' && typeof value !== 'string') {
    throw new TypeError('value must be a valid string');
  } else if (type === 'double' && !isFloatOrDouble(value) && !Number.isInteger(value)) {
    throw new TypeError('value must be a valid double or integer');
  } else if (type === 'boolean' && typeof value !== 'boolean') {
    throw new TypeError('value must be a valid boolean');
  } else if (type === 'array' && !Array.isArray(value)) {
    throw new TypeError('value must be a valid array');
  } else if (type == 'dictionary' && !isObject(value)) {
    throw new TypeError('value must be a valid dictionary');
  }

  return nsUbiquitousKeyValueStore.setValue.call(this, type, key, value);
}

function removeValue(key) {
  return nsUbiquitousKeyValueStore.removeValue.call(this, key);
}

function getDocumentDirectoryPath() {
  return nsUbiquitousKeyValueStore.getDocumentDirectoryPath.call(this);
}

function getiCloudDirectoryPath() {
  return nsUbiquitousKeyValueStore.getiCloudDirectoryPath.call(this);
}

module.exports = {
  getAllValues,
  getValue,
  setValue,
  removeValue,
  getDocumentDirectoryPath,
  getiCloudDirectoryPath,
  // Keychain exports
  keychainSetItem: function(params) {
    return nsUbiquitousKeyValueStore.keychainSetItem.call(this, params);
  },
  keychainGetItem: function(params) {
    return nsUbiquitousKeyValueStore.keychainGetItem.call(this, params);
  },
  keychainRemoveItem: function(params) {
    return nsUbiquitousKeyValueStore.keychainRemoveItem.call(this, params);
  },
  keychainHasItem: function(params) {
    return nsUbiquitousKeyValueStore.keychainHasItem.call(this, params);
  },
  keychainIsICloudSyncEnabled: function() {
    return nsUbiquitousKeyValueStore.keychainIsICloudSyncEnabled.call(this);
  },
  // CloudKit exports
  cloudkitIsAvailable: function() {
    return nsUbiquitousKeyValueStore.cloudkitIsAvailable.call(this);
  },
  cloudkitSaveRecord: function(params) {
    return nsUbiquitousKeyValueStore.cloudkitSaveRecord.call(this, params);
  },
  cloudkitFetchRecord: function(params) {
    return nsUbiquitousKeyValueStore.cloudkitFetchRecord.call(this, params);
  },
  cloudkitDeleteRecord: function(params) {
    return nsUbiquitousKeyValueStore.cloudkitDeleteRecord.call(this, params);
  },
  cloudkitRecordExists: function(params) {
    return nsUbiquitousKeyValueStore.cloudkitRecordExists.call(this, params);
  },
  cloudkitQueryRecords: function(params) {
    return nsUbiquitousKeyValueStore.cloudkitQueryRecords.call(this, params);
  },
};
