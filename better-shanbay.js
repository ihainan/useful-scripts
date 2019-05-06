// ==UserScript==
// @name         Better Shanbay
// @namespace    http://tampermonkey.net/
// @version      0.1
// @description  try to take over the world!
// @author       You
// @include      *shanbay.com*
// @grant        none
// ==/UserScript==
// @require http://code.jquery.com/jquery-3.3.1.min.js

(function () {
    'use strict';
    var $ = window.jQuery;
    console.log("Shanbay Word Page");

    function sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    $(".navbar").first().css("background-color", "#FFFFFF");

    var vTriggered = false;
    var vTabChanged = false;
    setInterval(function () {
        if ($('.defn-trigger').length) {
            if (!vTriggered) {
                console.log("Expand definition!");
                $('.defn-trigger')[0].click();
                vTriggered = true;
            }
        } else {
            vTriggered = false;
        }

        if ($('#note-mine-box').length) {
            if (!vTabChanged) {
                if ($("#note-mine-box").text().indexOf('你可以记录自己的笔记，或者收藏他人分享的') > -1) {
                    console.log("Display shared notes!");
                    $(".note-user-box-tab")[0].click();
                    vTabChanged = true;
                }
            }
        } else {
            vTabChanged = false;
        }

    }, 500);

    var currentWord = 7;
    setInterval(function () {
        if ($('.speaker.summary-speaker').length) {
            if (currentWord < 14) {
                console.log("Pronounce " + currentWord + "!");
                $('.speaker.summary-speaker')[currentWord].click();
                currentWord += 1;
            }
        } else {
            currentWord = 7
        }
    }, 3000);
})();
