const ART = String.raw`
     _         _   _                  _   _      _
    / \  _   _| |_| |__   ___  _ __  / \ | | ___| |_
   / _ \| | | | __| '_ \ / _ \| '__|/ _ \| |/ _ \ __|
  / ___ \ |_| | |_| | | | (_) | |  / ___ \ |  __/ |_
 /_/   \_\__,_|\__|_| |_|\___/|_| /_/   \_\_|\___|\__|
`;

export function welcome() {
    const message = `%c${ART}%c
AuroraNet — Secure access, simply connected.

WEBSITE:      https://aurora-net.org/
`;

    // Intentional AuroraNet ASCII banner in the devtools console.
    // eslint-disable-next-line no-console
    console.log(
        message,
        "color: #2dbe82; font-family: monospace; font-weight: normal; line-height: 1;",
        "color: #f4f7fa; font-family: monospace; font-weight: normal; line-height: 1.4;",
    );
}
