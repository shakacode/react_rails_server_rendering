import type { ReactElement } from 'react';
import type { Readable, PassThrough } from 'stream';

import * as ClientStartup from './clientStartup';
import handleError from './handleError';
import ComponentRegistry from './ComponentRegistry';
import StoreRegistry from './StoreRegistry';
import serverRenderReactComponent, { streamServerRenderedReactComponent } from './serverRenderReactComponent';
import buildConsoleReplay from './buildConsoleReplay';
import createReactOutput from './createReactOutput';
import Authenticity from './Authenticity';
import context from './context';
import type {
  RegisteredComponent,
  RenderParams,
  RenderResult,
  RenderReturnType,
  ErrorOptions,
  ReactComponentOrRenderFunction,
  AuthenticityHeaders,
  Store,
  StoreGenerator,
} from './types';
import reactHydrateOrRender from './reactHydrateOrRender';

const ctx = context();

if (ctx === undefined) {
  throw new Error("The context (usually Window or NodeJS's Global) is undefined.");
}

if (ctx.ReactOnRails !== undefined) {
  throw new Error(`
    The ReactOnRails value exists in the ${ctx} scope, it may not be safe to overwrite it.
    
    This could be caused by setting Webpack's optimization.runtimeChunk to "true" or "multiple," rather than "single." Check your Webpack configuration.
    
    Read more at https://github.com/shakacode/react_on_rails/issues/1558.
  `);
}

const DEFAULT_OPTIONS = {
  traceTurbolinks: false,
  turbo: false,
};

ctx.ReactOnRails = {
  options: {},
  /**
   * Main entry point to using the react-on-rails npm package. This is how Rails will be able to
   * find you components for rendering.
   * @param components (key is component name, value is component)
   */
  register(components: { [id: string]: ReactComponentOrRenderFunction }): void {
    ComponentRegistry.register(components);
  },

  registerStore(stores: { [id: string]: StoreGenerator }): void {
    this.registerStoreGenerators(stores);
  },

  /**
   * Allows registration of store generators to be used by multiple React components on one Rails
   * view. store generators are functions that take one arg, props, and return a store. Note that
   * the setStore API is different in that it's the actual store hydrated with props.
   * @param storeGenerators (keys are store names, values are the store generators)
   */
  registerStoreGenerators(storeGenerators: { [id: string]: StoreGenerator }): void {
    if (!storeGenerators) {
      throw new Error('Called ReactOnRails.registerStoreGenerators with a null or undefined, rather than ' +
        'an Object with keys being the store names and the values are the store generators.');
    }

    StoreRegistry.register(storeGenerators);
  },

  /**
   * Allows retrieval of the store by name. This store will be hydrated by any Rails form props.
   * Pass optional param throwIfMissing = false if you want to use this call to get back null if the
   * store with name is not registered.
   * @param name
   * @param throwIfMissing Defaults to true. Set to false to have this call return undefined if
   *        there is no store with the given name.
   * @returns Redux Store, possibly hydrated
   */
  getStore(name: string, throwIfMissing = true): Store | undefined {
    return StoreRegistry.getStore(name, throwIfMissing);
  },

  /**
   * Renders or hydrates the react element passed. In case react version is >=18 will use the new api.
   * @param domNode
   * @param reactElement
   * @param hydrate if true will perform hydration, if false will render
   * @returns {Root|ReactComponent|ReactElement|null}
   */
  reactHydrateOrRender(domNode: Element, reactElement: ReactElement, hydrate: boolean): RenderReturnType {
    return reactHydrateOrRender(domNode, reactElement, hydrate);
  },

  /**
   * Set options for ReactOnRails, typically before you call ReactOnRails.register
   * Available Options:
   * `traceTurbolinks: true|false Gives you debugging messages on Turbolinks events
   * `turbo: true|false Turbo (the follower of Turbolinks) events will be registered, if set to true.
   */
  setOptions(newOptions: {traceTurbolinks?: boolean, turbo?: boolean }): void {
    if (typeof newOptions.traceTurbolinks !== 'undefined') {
      this.options.traceTurbolinks = newOptions.traceTurbolinks;

      // eslint-disable-next-line no-param-reassign
      delete newOptions.traceTurbolinks;
    }

    if (typeof newOptions.turbo !== 'undefined') {
      this.options.turbo = newOptions.turbo;

      // eslint-disable-next-line no-param-reassign
      delete newOptions.turbo;
    }

    if (Object.keys(newOptions).length > 0) {
      throw new Error(
        `Invalid options passed to ReactOnRails.options: ${JSON.stringify(newOptions)}`,
      );
    }
  },

  /**
   * Allow directly calling the page loaded script in case the default events that trigger react
   * rendering are not sufficient, such as when loading JavaScript asynchronously with TurboLinks:
   * More details can be found here:
   * https://github.com/shakacode/react_on_rails/blob/master/docs/additional-reading/turbolinks.md
   */
  reactOnRailsPageLoaded(): void {
    ClientStartup.reactOnRailsPageLoaded();
  },

  renderOrHydrateLoadedComponents(): void {
    ClientStartup.renderOrHydrateLoadedComponents();
  },

  reactOnRailsComponentLoaded(domId: string): void {
    ClientStartup.reactOnRailsComponentLoaded(domId);
  },

  /**
   * Returns CSRF authenticity token inserted by Rails csrf_meta_tags
   * @returns String or null
   */

  authenticityToken(): string | null {
    return Authenticity.authenticityToken();
  },

  /**
   * Returns header with csrf authenticity token and XMLHttpRequest
   * @param otherHeaders Other headers
   * @returns {*} header
   */

  authenticityHeaders(otherHeaders: { [id: string]: string } = {}): AuthenticityHeaders {
    return Authenticity.authenticityHeaders(otherHeaders);
  },

  // /////////////////////////////////////////////////////////////////////////////
  // INTERNALLY USED APIs
  // /////////////////////////////////////////////////////////////////////////////

  /**
   * Retrieve an option by key.
   * @param key
   * @returns option value
   */
  option(key: string): string | number | boolean | undefined {
    return this.options[key];
  },

  /**
   * Allows retrieval of the store generator by name. This is used internally by ReactOnRails after
   * a Rails form loads to prepare stores.
   * @param name
   * @returns Redux Store generator function
   */
  getStoreGenerator(name: string): StoreGenerator {
    return StoreRegistry.getStoreGenerator(name);
  },

  /**
   * Allows saving the store populated by Rails form props. Used internally by ReactOnRails.
   * @param name
   * @returns Redux Store, possibly hydrated
   */
  setStore(name: string, store: Store): void {
    return StoreRegistry.setStore(name, store);
  },

  /**
   * Clears hydratedStores to avoid accidental usage of wrong store hydrated in previous/parallel
   * request.
   */
  clearHydratedStores(): void {
    StoreRegistry.clearHydratedStores();
  },

  /**
   * @example
   * ReactOnRails.render("HelloWorldApp", {name: "Stranger"}, 'app');
   *
   * Does this:
   * ```js
   * ReactDOM.render(React.createElement(HelloWorldApp, {name: "Stranger"}),
   *   document.getElementById('app'))
   * ```
   * under React 16/17 and
   * ```js
   * const root = ReactDOMClient.createRoot(document.getElementById('app'))
   * root.render(React.createElement(HelloWorldApp, {name: "Stranger"}))
   * return root
   * ```
   * under React 18+.
   *
   * @param name Name of your registered component
   * @param props Props to pass to your component
   * @param domNodeId
   * @param hydrate Pass truthy to update server rendered html. Default is falsy
   * @returns {Root|ReactComponent|ReactElement} Under React 18+: the created React root
   *   (see "What is a root?" in https://github.com/reactwg/react-18/discussions/5).
   *   Under React 16/17: Reference to your component's backing instance or `null` for stateless components.
   */
  render(name: string, props: Record<string, string>, domNodeId: string, hydrate: boolean): RenderReturnType {
    const componentObj = ComponentRegistry.get(name);
    const reactElement = createReactOutput({ componentObj, props, domNodeId });

    return reactHydrateOrRender(document.getElementById(domNodeId) as Element, reactElement as ReactElement, hydrate);
  },

  /**
   * Get the component that you registered
   * @param name
   * @returns {name, component, renderFunction, isRenderer}
   */
  getComponent(name: string): RegisteredComponent {
    return ComponentRegistry.get(name);
  },

  /**
   * Get the component that you registered, or wait for it to be registered
   * @param name
   * @returns {name, component, renderFunction, isRenderer}
   */
  getOrWaitForComponent(name: string): Promise<RegisteredComponent> {
    return ComponentRegistry.getOrWaitForComponent(name);
  },

  /**
   * Used by server rendering by Rails
   * @param options
   */
  serverRenderReactComponent(options: RenderParams): null | string | Promise<RenderResult> {
    return serverRenderReactComponent(options);
  },

  /**
   * Used by server rendering by Rails
   * @param options
   */
  streamServerRenderedReactComponent(options: RenderParams): Readable {
    return streamServerRenderedReactComponent(options);
  },

  /**
   * Used by rsc payload generation by Rails
   */
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  serverRenderRSCReactComponent(options: RenderParams): PassThrough {
    throw new Error('serverRenderRSCReactComponent is supported in RSC bundle only.');
  },

  /**
   * Used by Rails to catch errors in rendering
   * @param options
   */
  handleError(options: ErrorOptions): string | undefined {
    return handleError(options);
  },

  /**
   * Used by Rails server rendering to replay console messages.
   */
  buildConsoleReplay(): string {
    return buildConsoleReplay();
  },

  /**
   * Get an Object containing all registered components. Useful for debugging.
   * @returns {*}
   */
  registeredComponents(): Map<string, RegisteredComponent> {
    return ComponentRegistry.components();
  },

  /**
   * Get an Object containing all registered store generators. Useful for debugging.
   * @returns {*}
   */
  storeGenerators(): Map<string, StoreGenerator> {
    return StoreRegistry.storeGenerators();
  },

  /**
   * Get an Object containing all hydrated stores. Useful for debugging.
   * @returns {*}
   */
  stores(): Map<string, Store> {
    return StoreRegistry.stores();
  },

  resetOptions(): void {
    this.options = Object.assign({}, DEFAULT_OPTIONS);
  },
};

ctx.ReactOnRails.resetOptions();

ClientStartup.clientStartup(ctx);

export * from "./types";
export default ctx.ReactOnRails;
