import React from 'react';
import {
  type RegisteredComponent,
  type ReactComponentOrRenderFunction,
  type RenderFunction,
  type ItemRegistrationCallback,
} from './types';
import isRenderFunction from './isRenderFunction';
import CallbackRegistry from './CallbackRegistry';

const componentRegistry = new CallbackRegistry<RegisteredComponent>();

export default {
  /**
   * Register a callback to be called when a specific component is registered
   * @param componentName Name of the component to watch for
   * @param callback Function called with the component details when registered
   */
  onComponentRegistered(
    componentName: string,
    callback: ItemRegistrationCallback<RegisteredComponent>,
  ): void {
    componentRegistry.onItemRegistered(componentName, callback);
  },

  /**
   * @param components { component1: component1, component2: component2, etc. }
   */
  register(components: { [id: string]: ReactComponentOrRenderFunction }): void {
    Object.keys(components).forEach(name => {
      if (componentRegistry.has(name)) {
        console.warn('Called register for component that is already registered', name);
      }

      const component = components[name];
      if (!component) {
        throw new Error(`Called register with null component named ${name}`);
      }

      const renderFunction = isRenderFunction(component);
      const isRenderer = renderFunction && (component as RenderFunction).length === 3;

      componentRegistry.set(name, {
        name,
        component,
        renderFunction,
        isRenderer,
      });
    });
  },

  registerServerComponent(...componentNames: string[]): void {
    // eslint-disable-next-line global-require, @typescript-eslint/no-var-requires
    const RSCClientRoot = (require('./RSCClientRoot') as typeof import('./RSCClientRoot')).default;

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
    const component = componentRegistry.get(name);
    if (component !== undefined) return component;

    const keys = Array.from(componentRegistry.getAll().keys()).join(', ');
    throw new Error(`Could not find component registered with name ${name}. \
Registered component names include [ ${keys} ]. Maybe you forgot to register the component?`);
  },

  getOrWaitForComponent(name: string): Promise<RegisteredComponent> {
    return componentRegistry.getOrWaitForItem(name);
  },

  /**
   * Get a Map containing all registered components. Useful for debugging.
   * @returns Map where key is the component name and values are the
   * { name, component, renderFunction, isRenderer}
   */
  components(): Map<string, RegisteredComponent> {
    return componentRegistry.getAll();
  },
};
