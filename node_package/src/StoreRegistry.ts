import type { Store, StoreGenerator } from './types';

const registeredStoreGenerators = new Map<string, StoreGenerator>();
const hydratedStores = new Map<string, Store>();
const hydrationCallbacks = new Map<string, Array<(store: Store) => void>>();
const generatorCallbacks = new Map<string, Array<(generator: StoreGenerator) => void>>();

export default {
  /**
   * Register a store generator, a function that takes props and returns a store.
   * @param storeGenerators { name1: storeGenerator1, name2: storeGenerator2 }
   */
  register(storeGenerators: { [id: string]: StoreGenerator }): void {
    Object.keys(storeGenerators).forEach(name => {
      if (registeredStoreGenerators.has(name)) {
        console.warn('Called registerStore for store that is already registered', name);
      }

      const store = storeGenerators[name];
      if (!store) {
        throw new Error('Called ReactOnRails.registerStores with a null or undefined as a value ' +
          `for the store generator with key ${name}.`);
      }

      registeredStoreGenerators.set(name, store);

      const callbacks = generatorCallbacks.get(name) || [];
      callbacks.forEach(callback => {
        setTimeout(() => callback(store), 0);
      });
      generatorCallbacks.delete(name);
    });
  },

  /**
   * Used by components to get the hydrated store which contains props.
   * @param name
   * @param throwIfMissing Defaults to true. Set to false to have this call return undefined if
   *        there is no store with the given name.
   * @returns Redux Store, possibly hydrated
   */
  getStore(name: string, throwIfMissing = true): Store | undefined {
    if (hydratedStores.has(name)) {
      return hydratedStores.get(name);
    }

    const storeKeys = Array.from(hydratedStores.keys()).join(', ');

    if (storeKeys.length === 0) {
      const msg =
`There are no stores hydrated and you are requesting the store ${name}.
This can happen if you are server rendering and either:
1. You do not call redux_store near the top of your controller action's view (not the layout)
   and before any call to react_component.
2. You do not render redux_store_hydration_data anywhere on your page.`;
      throw new Error(msg);
    }

    if (throwIfMissing) {
      console.log('storeKeys', storeKeys);
      throw new Error(`Could not find hydrated store with name '${name}'. ` +
        `Hydrated store names include [${storeKeys}].`);
    }

    return undefined;
  },

  /**
   * Internally used function to get the store creator that was passed to `register`.
   * @param name
   * @returns storeCreator with given name
   */
  getStoreGenerator(name: string): StoreGenerator {
    const registeredStoreGenerator = registeredStoreGenerators.get(name);
    if (registeredStoreGenerator) {
      return registeredStoreGenerator;
    }

    const storeKeys = Array.from(registeredStoreGenerators.keys()).join(', ');
    throw new Error(`Could not find store registered with name '${name}'. Registered store ` +
      `names include [ ${storeKeys} ]. Maybe you forgot to register the store?`);
  },

  /**
   * Internally used function to set the hydrated store after a Rails page is loaded.
   * @param name
   * @param store (not the storeGenerator, but the hydrated store)
   */
  setStore(name: string, store: Store): void {
    hydratedStores.set(name, store);
    
    const callbacks = hydrationCallbacks.get(name) || [];
    callbacks.forEach(callback => {
      setTimeout(() => callback(store), 0);
    });
    hydrationCallbacks.delete(name);
  },

  /**
   * Internally used function to completely clear hydratedStores Map.
   */
  clearHydratedStores(): void {
    hydratedStores.clear();
  },

  /**
   * Get a Map containing all registered store generators. Useful for debugging.
   * @returns Map where key is the component name and values are the store generators.
   */
  storeGenerators(): Map<string, StoreGenerator> {
    return registeredStoreGenerators;
  },

  /**
   * Get a Map containing all hydrated stores. Useful for debugging.
   * @returns Map where key is the component name and values are the hydrated stores.
   */
  stores(): Map<string, Store> {
    return hydratedStores;
  },

  /**
   * Register a callback to be called when a specific store is hydrated
   * @param storeName Name of the store to watch for
   * @param callback Function called with the store when hydrated
   */
  onStoreHydrated(
    storeName: string,
    callback: (store: Store) => void
  ): void {
    // If store is already hydrated, schedule callback
    const existingStore = hydratedStores.get(storeName);
    if (existingStore) {
      setTimeout(() => callback(existingStore), 0);
      return;
    }

    // Store callback for future hydration
    const callbacks = hydrationCallbacks.get(storeName) || [];
    callbacks.push(callback);
    hydrationCallbacks.set(storeName, callbacks);
  },

  /**
   * Used by components to get the hydrated store, waiting for it to be hydrated if necessary.
   * @param name Name of the store to wait for
   * @returns Promise that resolves with the Store once hydrated
   */
  async getOrWaitForStore(name: string): Promise<Store> {
    return new Promise((resolve) => {
      this.onStoreHydrated(name, resolve);
    });
  },

  /**
   * Register a callback to be called when a specific store generator is registered
   * @param storeName Name of the store generator to watch for
   * @param callback Function called with the store generator when registered
   */
  onStoreGeneratorRegistered(
    storeName: string,
    callback: (generator: StoreGenerator) => void
  ): void {
    // If generator is already registered, schedule callback
    const existingGenerator = registeredStoreGenerators.get(storeName);
    if (existingGenerator) {
      setTimeout(() => callback(existingGenerator), 0);
      return;
    }

    // Store callback for future registration
    const callbacks = generatorCallbacks.get(storeName) || [];
    callbacks.push(callback);
    generatorCallbacks.set(storeName, callbacks);
  },

  /**
   * Used by components to get the store generator, waiting for it to be registered if necessary.
   * @param name Name of the store generator to wait for
   * @returns Promise that resolves with the StoreGenerator once registered
   */
  async getOrWaitForStoreGenerator(name: string): Promise<StoreGenerator> {
    return new Promise((resolve) => {
      this.onStoreGeneratorRegistered(name, resolve);
    });
  },
};
