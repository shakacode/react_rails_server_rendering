import ReactDOM from 'react-dom';
import type { ReactElement } from 'react';
import type {
  RailsContext,
  RegisteredComponent,
  RenderFunction,
  Root,
} from './types';

import { reactOnRailsContext, type Context } from './context';
import createReactOutput from './createReactOutput';
import { isServerRenderHash } from './isServerRenderResult';
import reactHydrateOrRender from './reactHydrateOrRender';
import { supportsRootApi } from './reactApis';

const REACT_ON_RAILS_STORE_ATTRIBUTE = 'data-js-react-on-rails-store';

function delegateToRenderer(
  componentObj: RegisteredComponent,
  props: Record<string, string>,
  railsContext: RailsContext,
  domNodeId: string,
  trace: boolean,
): boolean {
  const { name, component, isRenderer } = componentObj;

  if (isRenderer) {
    if (trace) {
      console.log(`\
DELEGATING TO RENDERER ${name} for dom node with id: ${domNodeId} with props, railsContext:`,
        props, railsContext);
    }

    (component as RenderFunction)(props, railsContext, domNodeId);
    return true;
  }

  return false;
}

const getDomId = (domIdOrElement: string | Element): string => typeof domIdOrElement === 'string' ? domIdOrElement : domIdOrElement.getAttribute('data-dom-id') || '';

let currentContext: Context | null = null;
let currentRailsContext: RailsContext | null = null;

// caches context and railsContext to avoid re-parsing rails-context each time a component is rendered
// Cached values will be reset when unmountAll() is called
function getContextAndRailsContext(): { context: Context | null; railsContext: RailsContext | null } {
  // Return cached values if already set
  if (currentContext && currentRailsContext) {
    return { context: currentContext, railsContext: currentRailsContext };
  }

  currentContext = reactOnRailsContext();

  const el = document.getElementById('js-react-on-rails-context');
  if (!el || !el.textContent) {
    return { context: null, railsContext: null };
  }

  try {
    currentRailsContext = JSON.parse(el.textContent);
  } catch (e) {
    console.error('Error parsing rails context:', e);
    return { context: null, railsContext: null };
  }

  return { context: currentContext, railsContext: currentRailsContext };
}

class ComponentRenderer {
  private domNodeId: string;
  private state: 'unmounted' | 'rendering' | 'rendered';
  private root?: Root;
  private renderPromise?: Promise<void>;

  constructor(domIdOrElement: string | Element) {
    const domId = getDomId(domIdOrElement);
    this.domNodeId = domId;
    this.state = 'rendering';
    const el = typeof domIdOrElement === 'string' ? document.querySelector(`[data-dom-id=${domId}]`) : domIdOrElement;
    if (!el) return;

    const storeDependencies = el.getAttribute('data-store-dependencies');
    const storeDependenciesArray = storeDependencies ? JSON.parse(storeDependencies) as string[] : [];

    const { context, railsContext } = getContextAndRailsContext();
    if (!context || !railsContext) return;

    // Wait for all store dependencies to be loaded
    this.renderPromise = Promise.all(
      storeDependenciesArray.map(storeName => context.ReactOnRails.getOrWaitForStore(storeName)),
    ).then(() => {
        if (this.state === 'unmounted') return Promise.resolve();
        return this.render(el, context, railsContext);
      });
  }

  /**
   * Used for client rendering by ReactOnRails. Either calls ReactDOM.hydrate, ReactDOM.render, or
   * delegates to a renderer registered by the user.
   */
  private async render(el: Element, context: Context, railsContext: RailsContext): Promise<void> {
    // This must match lib/react_on_rails/helper.rb
    const name = el.getAttribute('data-component-name') || '';
    const { domNodeId } = this;
    const props = (el.textContent !== null) ? JSON.parse(el.textContent) : {};
    const trace = el.getAttribute('data-trace') === 'true';

    try {
      const domNode = document.getElementById(domNodeId);
      if (domNode) {
        const componentObj = await context.ReactOnRails.getOrWaitForComponent(name);
        if (this.state === 'unmounted') {
          return;
        }

        if (delegateToRenderer(componentObj, props, railsContext, domNodeId, trace)) {
          return;
        }

        // Hydrate if available and was server rendered
        // @ts-expect-error potentially present if React 18 or greater
        const shouldHydrate = !!(ReactDOM.hydrate || ReactDOM.hydrateRoot) && !!domNode.innerHTML;

        const reactElementOrRouterResult = createReactOutput({
          componentObj,
          props,
          domNodeId,
          trace,
          railsContext,
          shouldHydrate,
        });

        if (isServerRenderHash(reactElementOrRouterResult)) {
          throw new Error(`\
  You returned a server side type of react-router error: ${JSON.stringify(reactElementOrRouterResult)}
  You should return a React.Component always for the client side entry point.`);
        } else {
          const rootOrElement = reactHydrateOrRender(domNode, reactElementOrRouterResult as ReactElement, shouldHydrate);
          this.state = 'rendered';
          if (supportsRootApi) {
            this.root = rootOrElement as Root;
          }
        }
      }
    } catch (e: unknown) {
      const error = e instanceof Error ? e : new Error('Unknown error');
      console.error(error.message);
      error.message = `ReactOnRails encountered an error while rendering component: ${name}. See above error message.`
      throw error;
    }
  }

  unmount(): void {
    if (this.state === 'rendering') {
      this.state = 'unmounted';
      return;
    }
    this.state = 'unmounted';

    if (supportsRootApi) {
      this.root?.unmount();
      this.root = undefined;
    } else {
      const domNode = document.getElementById(this.domNodeId);
      if (!domNode) {
        return;
      }

      try {
        ReactDOM.unmountComponentAtNode(domNode);
      } catch (e: unknown) {
        const error = e instanceof Error ? e : new Error('Unknown error');
        console.info(`Caught error calling unmountComponentAtNode: ${error.message} for domNode`,
          domNode, error);
      }
    }
  }

  waitUntilRendered(): Promise<void> {
    if (this.state === 'rendering') {
      return this.renderPromise!;
    }
    return Promise.resolve();
  }
}

class StoreRenderer {
  private hydratePromise?: Promise<void>;
  private state: 'unmounted' | 'hydrating' | 'hydrated';

  constructor(storeDataElement: Element) {
    this.state = 'hydrating';
    const { context, railsContext } = getContextAndRailsContext();
    if (!context || !railsContext) {
      return;
    }

    const name = storeDataElement.getAttribute(REACT_ON_RAILS_STORE_ATTRIBUTE) || '';
    const props = (storeDataElement.textContent !== null) ? JSON.parse(storeDataElement.textContent) : {};
    this.hydratePromise = this.hydrate(context, railsContext, name, props);
  }

  private async hydrate(context: Context, railsContext: RailsContext, name: string, props: Record<string, string>) {
    const storeGenerator = await context.ReactOnRails.getOrWaitForStoreGenerator(name);
    if (this.state === 'unmounted') {
      return;
    }

    const store = storeGenerator(props, railsContext);
    context.ReactOnRails.setStore(name, store);
    this.state = 'hydrated';
  }

  waitUntilHydrated(): Promise<void> {
    if (this.state === 'hydrating') {
      return this.hydratePromise!;
    }
    return Promise.resolve();
  }

  unmount(): void {
    this.state = 'unmounted';
  }
}

const renderedRoots = new Map<string, ComponentRenderer>();

export function renderOrHydrateComponent(domIdOrElement: string | Element): ComponentRenderer | undefined {
  const domId = getDomId(domIdOrElement);
  let root = renderedRoots.get(domId);
  if (!root) {
    root = new ComponentRenderer(domIdOrElement);
    renderedRoots.set(domId, root);
  }
  return root;
}


export function renderOrHydrateForceLoadedComponents(): void {
  const els = document.querySelectorAll(`.js-react-on-rails-component[data-force-load="true"]`);
  els.forEach((el) => renderOrHydrateComponent(el));
}

export function renderOrHydrateAllComponents(): void {
  const els = document.querySelectorAll(`.js-react-on-rails-component`);
  els.forEach((el) => renderOrHydrateComponent(el));
}

function unmountAllComponents(): void {
  renderedRoots.forEach((root) => root.unmount());
  renderedRoots.clear();
  currentContext = null;
  currentRailsContext = null;
}

const storeRenderers = new Map<string, StoreRenderer>();

export async function hydrateStore(storeNameOrElement: string | Element) {
  const storeName = typeof storeNameOrElement === 'string' ? storeNameOrElement : storeNameOrElement.getAttribute(REACT_ON_RAILS_STORE_ATTRIBUTE) || '';
  let storeRenderer = storeRenderers.get(storeName);
  if (!storeRenderer) {
    const storeDataElement = typeof storeNameOrElement === 'string' ? document.querySelector(`[${REACT_ON_RAILS_STORE_ATTRIBUTE}="${storeNameOrElement}"]`) : storeNameOrElement;
    if (!storeDataElement) {
      return;
    }

    storeRenderer = new StoreRenderer(storeDataElement);
    storeRenderers.set(storeName, storeRenderer);
  }
  await storeRenderer.waitUntilHydrated();
}

export async function hydrateForceLoadedStores(): Promise<void> {
  const els = document.querySelectorAll(`[${REACT_ON_RAILS_STORE_ATTRIBUTE}][data-force-load="true"]`);
  await Promise.all(Array.from(els).map((el) => hydrateStore(el)));
}

export async function hydrateAllStores(): Promise<void> {
  const els = document.querySelectorAll(`[${REACT_ON_RAILS_STORE_ATTRIBUTE}]`);
  await Promise.all(Array.from(els).map((el) => hydrateStore(el)));
}

function unmountAllStores(): void {
  storeRenderers.forEach((storeRenderer) => storeRenderer.unmount());
  storeRenderers.clear();
}

export function unmountAll(): void {
  unmountAllComponents();
  unmountAllStores();
}
