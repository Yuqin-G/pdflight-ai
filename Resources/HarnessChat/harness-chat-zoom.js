import { isHarnessWebKit } from './harness-webkit-compat.js';

// Adapted from DeepSeek Harness pdf-reading-mode/client.js (MIT license).
// The hook keeps the original gesture, wheel, clamping, flushSync, and storage
// behavior. React and flushSync are supplied by the bundled Harness runtime.
const CHAT_ZOOM_KEY = 'pdf-reading-chat-zoom';
const CHAT_ZOOM_MIN = .8, CHAT_ZOOM_MAX = 2.4;
// WebKit's CSS zoom reselects the optical size of system fonts, rounds line
// heights, and scales container-query lengths twice. Keep layout at the
// original font size and scale its paint instead, as Chromium's zoom does.


function storedChatZoom() {
  try {
    const value = Number(window.localStorage.getItem(CHAT_ZOOM_KEY));
    return Number.isFinite(value) && value >= CHAT_ZOOM_MIN && value <= CHAT_ZOOM_MAX ? value : 1;
  } catch (_) { return 1; }
}

export function useHarnessChatZoom(React, flushSync, chatBody) {
  const { useEffect, useRef, useState } = React;
  const [chatZoom, setChatZoom] = useState(storedChatZoom);
  const chatZoomRef = useRef(chatZoom), chatZoomSave = useRef(null);
  const applyRef = useRef(null);
  useEffect(() => {
    const element = chatBody.current;
    if (!element) return;
    element.dataset.chatZoom = String(chatZoom);
    if (isHarnessWebKit) {
      element.style.zoom = '';
      element.style.position = 'absolute';
      element.style.inset = '0 auto auto 0';
      element.style.width = `calc(100% / ${chatZoom})`;
      element.style.height = `calc(100% / ${chatZoom})`;
      element.style.transformOrigin = 'top left';
      element.style.transform = `scale(${chatZoom})`;
    } else {
      element.style.zoom = String(chatZoom);
    }
    clearTimeout(chatZoomSave.current);
    chatZoomSave.current = setTimeout(() => {
      try { window.localStorage.setItem(CHAT_ZOOM_KEY, String(chatZoom)); } catch (_) {}
    }, 260);
  }, [chatZoom]);
  useEffect(() => () => {
    clearTimeout(chatZoomSave.current);
    try { window.localStorage.setItem(CHAT_ZOOM_KEY, String(chatZoomRef.current)); } catch (_) {}
  }, []);
  useEffect(() => {
    const element = chatBody.current;
    if (!element) return;
    const apply = next => {
      if (!Number.isFinite(next)) return;
      const value = Math.min(CHAT_ZOOM_MAX, Math.max(CHAT_ZOOM_MIN, next));
      if (Math.abs(value - chatZoomRef.current) < .001) return;
      chatZoomRef.current = value;
      flushSync(() => setChatZoom(value));
      window.webkit?.messageHandlers?.harnessZoom?.postMessage({ zoom: value });
    };
    applyRef.current = apply;
    const wheel = event => {
      if (!(event.ctrlKey || event.metaKey)) return;
      event.preventDefault();
      apply(chatZoomRef.current * Math.exp(-event.deltaY * .004));
    };
    let start = 1;
    const begin = event => { event.preventDefault(); start = chatZoomRef.current; };
    const change = event => { event.preventDefault(); apply(start * event.scale); };
    const end = event => { event.preventDefault(); };
    element.addEventListener('wheel', wheel, { passive: false });
    element.addEventListener('gesturestart', begin, { passive: false });
    element.addEventListener('gesturechange', change, { passive: false });
    element.addEventListener('gestureend', end, { passive: false });
    return () => {
      applyRef.current = null;
      element.removeEventListener('wheel', wheel);
      element.removeEventListener('gesturestart', begin);
      element.removeEventListener('gesturechange', change);
      element.removeEventListener('gestureend', end);
    };
  }, []);
  return { chatZoom, applyRef };
}
