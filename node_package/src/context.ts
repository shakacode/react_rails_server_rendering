import { ReactOnRails as ReactOnRailsType } from './types';
import * as ClientStartup from './clientStartup';

/**
 * Get the context, be it window or global
 * @returns {boolean|Window|*|context}
 */
export function context(this: void): Window | NodeJS.Global | void {
  return ((typeof window !== 'undefined') && window) ||
    ((typeof global !== 'undefined') && global) ||
    this;
}

export const setReactOnRails = (value: ReactOnRailsType) => {
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

  ctx.ReactOnRails = value;

  ctx.ReactOnRails.resetOptions();

  ClientStartup.clientStartup(ctx);
};
