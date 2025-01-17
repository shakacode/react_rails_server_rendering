const { pathToFileURL } = require('url');

const RSCWebpackLoader = async function Loader(source, sourceMap) {
  // Mark loader as async since we're doing async operations
  const callback = this.async();

  try {
    // Convert file path to URL format
    const fileUrl = pathToFileURL(this.resourcePath).href;

    // eslint-plugin-import currently does not support subpaths: https://github.com/import-js/eslint-plugin-import/issues/3076
    const { load } = await import('react-server-dom-webpack/node-loader'); // eslint-disable-line import/no-unresolved
    const result = await load(fileUrl, null, async () => ({
      format: 'module',
      source,
    }));

    callback(null, result.source, sourceMap);
  } catch (error) {
    callback(error);
  }
};

module.exports = RSCWebpackLoader;
