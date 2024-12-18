import { ItemRegistrationCallback } from "./types";

export default class CallbackRegistry<T> {
  private registeredItems = new Map<string, T>();
  private callbacks = new Map<string, Array<ItemRegistrationCallback<T>>>();

  set(name: string, item: T): void {
    this.registeredItems.set(name, item);
    
    const callbacks = this.callbacks.get(name) || [];
    callbacks.forEach(callback => {
      setTimeout(() => callback(item), 0);
    });
    this.callbacks.delete(name);
  }

  get(name: string): T | undefined {
    return this.registeredItems.get(name);
  }

  has(name: string): boolean {
    return this.registeredItems.has(name);
  }

  clear(): void {
    this.registeredItems.clear();
  }

  getAll(): Map<string, T> {
    return this.registeredItems;
  }

  onItemRegistered(name: string, callback: ItemRegistrationCallback<T>): void {
    const existingItem = this.registeredItems.get(name);
    if (existingItem) {
      setTimeout(() => callback(existingItem), 0);
      return;
    }

    const callbacks = this.callbacks.get(name) || [];
    callbacks.push(callback);
    this.callbacks.set(name, callbacks);
  }

  getOrWaitForItem(name: string): Promise<T> {
    return new Promise((resolve) => {
      this.onItemRegistered(name, resolve);
    });
  }
}
