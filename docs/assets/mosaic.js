(function () {
  var canvas = document.getElementById("mosaic");
  if (!canvas) return;
  var ctx = canvas.getContext("2d");
  var dpr = window.devicePixelRatio || 1;
  canvas.width = 128 * dpr;
  canvas.height = 128 * dpr;
  ctx.scale(dpr, dpr);

  // Fixed (non-random) diamond mosaic so the mark is stable across reloads,
  // echoing the app icon's heatmap-square motif.
  var grid = [
    [null, null, null, 0, 1, null, null, null],
    [null, null, 1, 2, 0, 3, null, null],
    [null, 2, 0, 1, 3, 0, 1, null],
    [1, 3, 0, 2, 1, 0, 3, 2],
    [0, 1, 3, 0, 2, 1, 0, 1],
    [null, 0, 2, 1, 0, 3, 1, null],
    [null, null, 3, 0, 1, 2, null, null],
    [null, null, null, 2, 0, null, null, null],
  ];

  function shades() {
    var dark = window.matchMedia("(prefers-color-scheme: dark)").matches;
    var theme = document.documentElement.getAttribute("data-theme");
    if (theme === "dark") dark = true;
    if (theme === "light") dark = false;
    return dark
      ? ["#2f5a34", "#4d8a4a", "#7fcb74", "#bfe8b6"]
      : ["#245029", "#3d7a42", "#5fa35a", "#a9d9a0"];
  }

  function draw() {
    var cell = 128 / 8;
    var gap = 2;
    var colors = shades();
    ctx.clearRect(0, 0, 128, 128);
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        var v = grid[r][c];
        if (v === null) continue;
        ctx.fillStyle = colors[v];
        ctx.fillRect(c * cell + gap / 2, r * cell + gap / 2, cell - gap, cell - gap);
      }
    }
  }

  draw();
  window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", draw);
  new MutationObserver(draw).observe(document.documentElement, {
    attributes: true,
    attributeFilter: ["data-theme"],
  });
})();
