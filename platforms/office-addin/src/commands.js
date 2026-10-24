/* FunctionFile of the add-in manifest: Office needs it loaded, the button itself just shows the task pane. */
(function () {
  'use strict';
  if (window.Office && Office.onReady) Office.onReady(function () {});
  else if (window.Office) Office.initialize = function () {};
})();
