import React from 'react';
import type { RegisteredComponent, ReactComponentOrRenderFunction, RenderFunction, ReactComponent } from './types/index';
import isRenderFunction from './isRenderFunction';

const registeredComponents = new Map<string, RegisteredComponent>();
const registrationCallbacks = new Map<string, Array<(component: RegisteredComponent) => void>>();

export default {
  /**
   * Register a callback to be called when a specific component is registered
   * @param componentName Name of the component to watch for
   * @param callback Function called with the component details when registered
   */
  onComponentRegistered(
    componentName: string, 
    callback: (component: RegisteredComponent) => void
  ): void {
    // If component is already registered, schedule callback
    const existingComponent = registeredComponents.get(componentName);
    if (existingComponent) {
      setTimeout(() => callback(existingComponent), 0);
      return;
    }

    // Store callback for future registration
    const callbacks = registrationCallbacks.get(componentName) || [];
    callbacks.push(callback);
    registrationCallbacks.set(componentName, callbacks);
  },

  /**
   * @param components { component1: component1, component2: component2, etc. }
   */
  register(components: { [id: string]: ReactComponentOrRenderFunction }): void {
    Object.keys(components).forEach(name => {
      if (registeredComponents.has(name)) {
        console.warn('Called register for component that is already registered', name);
      }

      const component = components[name];
      if (!component) {
        throw new Error(`Called register with null component named ${name}`);
      }

      const renderFunction = isRenderFunction(component);
      const isRenderer = renderFunction && (component as RenderFunction).length === 3;

      const registeredComponent = {
        name,
        component,
        renderFunction,
        isRenderer,
      };
      registeredComponents.set(name, registeredComponent);

      const callbacks = registrationCallbacks.get(name) || [];
      callbacks.forEach(callback => {
        setTimeout(() => callback(registeredComponent), 0);
      });
      registrationCallbacks.delete(name);
    });
  },

  registerServerComponent(...componentNames: string[]): void {
    // eslint-disable-next-line global-require, @typescript-eslint/no-var-requires
    const RSCClientRoot = require('./RSCClientRoot').default;

    const componentsWrappedInRSCClientRoot = componentNames.reduce(
      (acc, name) => ({ ...acc, [name]: () => React.createElement(RSCClientRoot, { componentName: name }) }),
      {}
    );
    this.register(componentsWrappedInRSCClientRoot);
  },

  /**
   * @param name
   * @returns { name, component, isRenderFunction, isRenderer }
   */
  get(name: string): RegisteredComponent {
    const registeredComponent = registeredComponents.get(name);
    if (registeredComponent !== undefined) {
      return registeredComponent;
    }

    const keys = Array.from(registeredComponents.keys()).join(', ');
    throw new Error(`Could not find component registered with name ${name}. \
Registered component names include [ ${keys} ]. Maybe you forgot to register the component?`);
  },

  async getOrWaitForComponent(name: string): Promise<RegisteredComponent> {
    return new Promise((resolve) => {
      this.onComponentRegistered(name, resolve);
    });
  },

  /**
   * Get a Map containing all registered components. Useful for debugging.
   * @returns Map where key is the component name and values are the
   * { name, component, renderFunction, isRenderer}
   */
  components(): Map<string, RegisteredComponent> {
    return registeredComponents;
  },
};
