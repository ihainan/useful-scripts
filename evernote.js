// ==UserScript==
// @name         Evernote Highlight
// @namespace    http://tampermonkey.net/
// @version      0.1
// @description  try to take over the world!
// @author       You
// @match        https://www.evernote.com/client/*
// @grant        none
// ==/UserScript==
// @require http://code.jquery.com/jquery-3.3.1.min.js
// @require https://unpkg.com/hotkeys-js/dist/hotkeys.min.js

(function () {
    'use strict';

    document.onkeyup = function (e) {
        if (e.ctrlKey && e.shiftKey && e.which == 72) {
            let color = "#FFFF00";
            document.querySelector("iframe").contentDocument.execCommand("hiliteColor", false, color)
        }
    };
})();
