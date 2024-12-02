import type { ReactElement, ReactNode, Component, ComponentType } from 'react';
import type { Readable, PassThrough } from 'stream';

// Don't import redux just for the type definitions
// See https://github.com/shakacode/react_on_rails/issues/1321
// and https://redux.js.org/api/store for the actual API.
/* eslint-disable @typescript-eslint/no-explicit-any */
type Store = unknown;

type ReactComponent = ComponentType<any> | string;

// Keep these in sync with method lib/react_on_rails/helper.rb#rails_context
export interface RailsContext {
  railsEnv: string;
  inMailer: boolean;
  i18nLocale: string;
  i18nDefaultLocale: string;
  rorVersion: string;
  rorPro: boolean;
  rorProVersion?: string;
  serverSide: boolean;
  href: string;
  location: string;
  scheme: string;
  host: string;
  port: number | null;
  pathname: string;
  search: string | null;
  httpAcceptLanguage: string;
}

type AuthenticityHeaders = {[id: string]: string} & {'X-CSRF-Token': string | null; 'X-Requested-With': string};

type StoreGenerator = (props: Record<string, unknown>, railsContext: RailsContext) => Store

interface ServerRenderResult {
  renderedHtml?: string | { componentHtml: string; [key: string]: string };
  redirectLocation?: {pathname: string; search: string};
  routeError?: Error;
  error?: Error;
}

type CreateReactOutputResult = ServerRenderResult | ReactElement | Promise<string>;

type RenderFunctionResult = ReactComponent | ServerRenderResult | Promise<string>;

/**
 * Render functions are used to create dynamic React components or server-rendered HTML with side effects.
 * They receive two arguments: props and railsContext.
 * 
 * @param props - The component props passed to the render function
 * @param railsContext - The Rails context object containing environment information
 * @returns A string, React component, React element, or a Promise resolving to a string
 * 
 * @remarks
 * To distinguish a render function from a React Function Component:
 * 1. Ensure it accepts two parameters (props and railsContext), even if railsContext is unused, or
 * 2. Set the `renderFunction` property to `true` on the function object.
 * 
 * If neither condition is met, it will be treated as a React Function Component,
 * and ReactDOMServer will attempt to render it.
 * 
 * @example
 * // Option 1: Two-parameter function
 * const renderFunction = (props, railsContext) => { ... };
 * 
 * // Option 2: Using renderFunction property
 * const anotherRenderFunction = (props) => { ... };
 * anotherRenderFunction.renderFunction = true;
 */
interface RenderFunction {
  (props?: any, railsContext?: RailsContext, domNodeId?: string): RenderFunctionResult;
  // We allow specifying that the function is RenderFunction and not a React Function Component
  // by setting this property
  renderFunction?: true;
}

type ReactComponentOrRenderFunction = ReactComponent | RenderFunction;

export type { // eslint-disable-line import/prefer-default-export
  ReactComponentOrRenderFunction,
  ReactComponent,
  AuthenticityHeaders,
  RenderFunction,
  RenderFunctionResult,
  Store,
  StoreGenerator,
  CreateReactOutputResult,
  ServerRenderResult,
}

export interface RegisteredComponent {
  name: string;
  component: ReactComponentOrRenderFunction;
  /**
   * Indicates if the registered component is a RenderFunction
   * @see RenderFunction for more details on its behavior and usage.
   */
  renderFunction: boolean;
  // Indicates if the registered component is a Renderer function.
  // Renderer function handles DOM rendering or hydration with 3 args: (props, railsContext, domNodeId)
  // Supported on the client side only.
  // All renderer functions are render functions, but not all render functions are renderer functions.
  isRenderer: boolean;
}

interface Params {
  props?: Record<string, unknown>;
  railsContext?: RailsContext;
  domNodeId?: string;
  trace?: boolean;
}

export interface RenderParams extends Params {
  name: string;
  throwJsErrors: boolean;
  renderingReturnsPromises: boolean;
}

export interface CreateParams extends Params {
  componentObj: RegisteredComponent;
  shouldHydrate?: boolean;
}

export interface ErrorOptions {
  // fileName and lineNumber are non-standard, but useful if present
  // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Error/fileName
  e: Error & { fileName?: string; lineNumber?: string };
  name?: string;
  jsCode?: string;
  serverSide: boolean;
}

export type RenderingError = Pick<Error, 'message' | 'stack'>;

export interface RenderResult {
  html: string | null;
  consoleReplayScript: string;
  hasErrors: boolean;
  renderingError?: RenderingError;
  isShellReady?: boolean;
}

// from react-dom 18
export interface Root {
  render(children: ReactNode): void;
  unmount(): void;
}

export type RenderReturnType = void | Element | Component | Root;

export interface ReactOnRails {
  register(components: { [id: string]: ReactComponentOrRenderFunction }): void;
  registerServerComponent(...componentNames: string[]): void;
  /** @deprecated Use registerStoreGenerators instead */
  registerStore(stores: { [id: string]: StoreGenerator }): void;
  registerStoreGenerators(storeGenerators: { [id: string]: StoreGenerator }): void;
  getStore(name: string, throwIfMissing?: boolean): Store | undefined;
  getOrWaitForStore(name: string): Promise<Store>;
  getOrWaitForStoreGenerator(name: string): Promise<StoreGenerator>;
  setOptions(newOptions: {traceTurbolinks: boolean}): void;
  reactHydrateOrRender(domNode: Element, reactElement: ReactElement, hydrate: boolean): RenderReturnType;
  reactOnRailsPageLoaded(): void;
  renderOrHydrateLoadedComponents(): void;
  hydratePendingStores(): void;
  reactOnRailsComponentLoaded(domId: string): void;
  authenticityToken(): string | null;
  authenticityHeaders(otherHeaders: { [id: string]: string }): AuthenticityHeaders;
  option(key: string): string | number | boolean | undefined;
  getStoreGenerator(name: string): StoreGenerator;
  setStore(name: string, store: Store): void;
  clearHydratedStores(): void;
  render(
    name: string, props: Record<string, string>, domNodeId: string, hydrate: boolean
  ): RenderReturnType;
  getComponent(name: string): RegisteredComponent;
  getOrWaitForComponent(name: string): Promise<RegisteredComponent>;
  serverRenderReactComponent(options: RenderParams): null | string | Promise<RenderResult>;
  streamServerRenderedReactComponent(options: RenderParams): Readable;
  serverRenderRSCReactComponent(options: RenderParams): PassThrough;
  handleError(options: ErrorOptions): string | undefined;
  buildConsoleReplay(): string;
  registeredComponents(): Map<string, RegisteredComponent>;
  storeGenerators(): Map<string, StoreGenerator>;
  stores(): Map<string, Store>;
  resetOptions(): void;
  options: Record<string, string | number | boolean>;
}
