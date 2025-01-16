const { pathToFileURL } = require('url');

const RSCWebpackLoader = async function Loader(source, sourceMap) {
  // Mark loader as async since we're doing async operations
  const callback = this.async();
  
  try {
    // Convert file path to URL format
    const fileUrl = pathToFileURL(this.resourcePath).href;

    const { load } = await import('react-server-dom-webpack/node-loader');
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
