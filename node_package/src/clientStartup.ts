import { reactOnRailsContext, type Context } from './context';
import {
  renderOrHydrateForceLoadedComponents,
  renderOrHydrateAllComponents,
  hydrateForceLoadedStores,
  hydrateAllStores,
  unmountAll,
} from './ClientSideRenderer';

/* eslint-disable @typescript-eslint/no-explicit-any */

declare global {
  namespace Turbolinks {
    interface TurbolinksStatic {
      controller?: unknown;
    }
  }
}


function debugTurbolinks(...msg: string[]): void {
  if (!window) {
    return;
  }

  const context = reactOnRailsContext();
  if (context.ReactOnRails && context.ReactOnRails.option('traceTurbolinks')) {
    console.log('TURBO:', ...msg);
  }
}

function turbolinksInstalled(): boolean {
  return (typeof Turbolinks !== 'undefined');
}

function turboInstalled() {
  const context = reactOnRailsContext();
  if (context.ReactOnRails) {
    return context.ReactOnRails.option('turbo') === true;
  }
  return false;
}

function turbolinksVersion5(): boolean {
  return (typeof Turbolinks.controller !== 'undefined');
}

function turbolinksSupported(): boolean {
  return Turbolinks.supported;
}

export function reactOnRailsPageLoaded(): void {
  debugTurbolinks('reactOnRailsPageLoaded');
  hydrateAllStores();
  renderOrHydrateAllComponents();
}

function reactOnRailsPageUnloaded(): void {
  debugTurbolinks('reactOnRailsPageUnloaded');
  unmountAll();
}

function renderInit(): void {
  // Install listeners when running on the client (browser).
  // We must do this check for turbolinks AFTER the document is loaded because we load the
  // Webpack bundles first.
  if ((!turbolinksInstalled() || !turbolinksSupported()) && !turboInstalled()) {
    debugTurbolinks('NOT USING TURBOLINKS: calling reactOnRailsPageLoaded');
    reactOnRailsPageLoaded();
    return;
  }

  if (turboInstalled()) {
    debugTurbolinks(
      'USING TURBO: document added event listeners ' +
      'turbo:before-render and turbo:render.');
    document.addEventListener('turbo:before-render', reactOnRailsPageUnloaded);
    document.addEventListener('turbo:render', reactOnRailsPageLoaded);
    reactOnRailsPageLoaded();
  } else if (turbolinksVersion5()) {
    debugTurbolinks(
      'USING TURBOLINKS 5: document added event listeners ' +
      'turbolinks:before-render and turbolinks:render.');
    document.addEventListener('turbolinks:before-render', reactOnRailsPageUnloaded);
    document.addEventListener('turbolinks:render', reactOnRailsPageLoaded);
    reactOnRailsPageLoaded();
  } else {
    debugTurbolinks(
      'USING TURBOLINKS 2: document added event listeners page:before-unload and ' +
      'page:change.');
    document.addEventListener('page:before-unload', reactOnRailsPageUnloaded);
    document.addEventListener('page:change', reactOnRailsPageLoaded);
  }
}

function isWindow(context: Context): context is Window {
  return (context as Window).document !== undefined;
}

export function clientStartup(context: Context): void {
  // Check if server rendering
  if (!isWindow(context)) {
    return;
  }

  // Tried with a file local variable, but the install handler gets called twice.
  // eslint-disable-next-line no-underscore-dangle
  if (context.__REACT_ON_RAILS_EVENT_HANDLERS_RAN_ONCE__) {
    return;
  }

  // eslint-disable-next-line no-underscore-dangle, no-param-reassign
  context.__REACT_ON_RAILS_EVENT_HANDLERS_RAN_ONCE__ = true;

  if (document.readyState !== 'complete') {
    // force loaded components and stores are rendered and hydrated immediately
    renderOrHydrateForceLoadedComponents();
    hydrateForceLoadedStores();

    // Other components and stores are rendered and hydrated when the page is fully loaded
    document.addEventListener('DOMContentLoaded', renderInit);
  }
}
