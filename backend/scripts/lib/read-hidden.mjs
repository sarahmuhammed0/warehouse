// Reads a line from the TTY without echoing it.
//
// Shared by `db:provision` and `admin:create`, and extracted here rather than
// copied because the subtleties below are not obvious and a fix applied to one
// copy would not reach the other: chunked delivery under raw mode, two different
// backspace bytes depending on platform, and control characters that must be
// dropped rather than silently appended to a password nobody can see.

/**
 * @param {string} prompt written to stdout before reading
 * @returns {Promise<string>} what was typed, without the terminating newline
 */
export function readHidden(prompt) {
  return new Promise((resolve, reject) => {
    process.stdout.write(prompt);
    const stdin = process.stdin;

    if (!stdin.isTTY) {
      // Refusing is the point. Falling back to a visible read would echo the
      // password into the terminal, and into whatever is capturing it.
      reject(
        new Error(
          "No interactive terminal, so the password cannot be typed without being echoed. " +
            "Run this directly in a terminal window (not through a pipe, a CI step, or a " +
            "tool that captures output)."
        )
      );
      return;
    }

    stdin.setRawMode(true);
    stdin.resume();
    stdin.setEncoding("utf8");
    let value = "";

    const finish = (settle, arg) => {
      stdin.setRawMode(false);
      stdin.pause();
      stdin.removeListener("data", onData);
      process.stdout.write("\n");
      settle(arg);
    };

    // Raw mode delivers chunks, not single keystrokes — a fast typist or a paste
    // arrives as several characters at once, possibly including the terminating
    // newline. Each character is therefore handled on its own; treating a whole
    // chunk as one "char" would append the Enter to the password instead of
    // ending input.
    const onData = (chunk) => {
      for (const char of chunk) {
        // Enter (CR/LF) ends input; Ctrl-C and Ctrl-D abort.
        if (char === "\r" || char === "\n") return finish(resolve, value);
        if (char === "\u0003" || char === "\u0004") return finish(reject, new Error("Aborted."));

        // Backspace: Windows consoles send BS (0x08), Unix terminals send DEL
        // (0x7f). Both must edit, or a character the user erased stays in the
        // password on one platform or the other — silently, since there is no
        // echo to reveal it.
        if (char === "\u007f" || char === "\b") {
          value = value.slice(0, -1);
          continue;
        }

        // Drop any other control character (arrow keys arrive as escape
        // sequences) rather than letting it into the password.
        if (char < " ") continue;
        value += char;
      }
    };

    stdin.on("data", onData);
  });
}
