export default function transformRSCStreamAndReplayConsoleLogs(stream: ReadableStream) {
  return new ReadableStream({
    async start(controller) {
      const reader = stream.getReader();
      const decoder = new TextDecoder();
      const encoder = new TextEncoder();

      let { value, done } = await reader.read();
      while (!done) {
        const decodedValue = decoder.decode(value);
        const jsonChunks = decodedValue.split('\n')
          .filter(line => line.trim() !== '')
          .map((line) => {
            try {
              return JSON.parse(line);
            } catch (error) {
              console.error('Error parsing JSON:', line, error);
              throw error;
            }
          });

        for (const jsonChunk of jsonChunks) {
          const { html, consoleReplayScript } = jsonChunk;
          controller.enqueue(encoder.encode(html));

          const replayConsoleCode = consoleReplayScript?.trim().replace(/^<script.*>/, '').replace(/<\/script>$/, '');
          if (replayConsoleCode?.trim() !== '') {
            const scriptElement = document.createElement('script');
            scriptElement.textContent = replayConsoleCode;
            document.body.appendChild(scriptElement);
          }
        }

        // eslint-disable-next-line no-await-in-loop
        ({ value, done } = await reader.read());
      }
      controller.close();
    }
  });
}
