const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
await delay(180);
const area = document.getElementById('chat-body');
for (const element of area.querySelectorAll('*')) if (/auto|scroll/.test(getComputedStyle(element).overflowY)) element.scrollTop = 0;
await delay(60);
const base = area.getBoundingClientRect();
const zoom = Number(area.dataset.chatZoom || area.style.zoom || getComputedStyle(area).zoom) || 1;
const rect = element => {const r=element.getBoundingClientRect();return {left:r.left-base.left,right:r.right-base.left,top:r.top-base.top,bottom:r.bottom-base.top,width:r.width,height:r.height}};
const style = element => {const c=getComputedStyle(element);return Object.fromEntries(['fontFamily','fontSize','fontWeight','lineHeight','marginTop','marginBottom','paddingLeft','paddingRight','color','backgroundColor','borderTopWidth','borderBottomWidth','overflowX','maxWidth'].map(key=>[key,c[key]]))};
const lineCount = element => {
  if (!/^(P|H[1-6]|LI)$/.test(element.tagName) && !element.className.includes('_bubble')) return null;
  const css = getComputedStyle(element), lineHeight = parseFloat(css.lineHeight) * zoom;
  const centers = [], walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
  let node;
  while ((node = walker.nextNode())) {
    if (!node.length || node.parentElement.closest('.katex,[aria-hidden="true"]')) continue;
    const range = document.createRange(); range.selectNodeContents(node);
    for (const bounds of range.getClientRects()) {
      if (bounds.height <= 0) continue;
      const center = (bounds.top + bounds.bottom) / 2;
      if (!centers.some(other => Math.abs(other - center) < lineHeight * .45)) centers.push(center);
    }
  }
  // The synthetic inline formula can occupy a line without ordinary text.
  const contentHeight = element.getBoundingClientRect().height - (parseFloat(css.paddingTop) + parseFloat(css.paddingBottom)) * zoom;
  return Math.max(centers.length, Math.round(contentHeight / lineHeight));
};
const elements = [...area.querySelectorAll('h1,h2,p,li,pre,th,td,blockquote,.md-table-wide,[data-chat-flow], [data-chat-flow-kind="user"], [class*="_bubble"]')].map(element=>({tag:element.tagName,rect:rect(element),style:style(element),lineCount:lineCount(element)}));
const scroller=area.querySelector('[data-conversation-scroll]');
const context={sharedScroller:!!scroller,contentWidth:getComputedStyle(area.querySelector('[data-chat-flow]')).getPropertyValue('--dsh-chat-content-width').trim(),composerClearance:getComputedStyle(area.querySelector('[data-chat-flow]')).getPropertyValue('--dsh-composer-side-clearance').trim(),area:rect(area),pageOverflow:document.documentElement.scrollWidth-innerWidth};
const tables=[];
for(const wrapper of area.querySelectorAll('.md-table-wide')) {
  wrapper.focus({preventScroll:true});await delay(20);
  const table=wrapper.querySelector('table');wrapper.scrollLeft=0;const left=rect(table).left;
  wrapper.scrollLeft=wrapper.scrollWidth;
  tables.push({wrapper:rect(wrapper),tableRight:rect(table).right,left,range:wrapper.scrollLeft});
  wrapper.scrollLeft=0;wrapper.blur();
}
for (const element of area.querySelectorAll('*')) if (/auto|scroll/.test(getComputedStyle(element).overflowY)) element.scrollTop = 0;
if(window.__errors?.length) throw new Error(JSON.stringify(window.__errors));
return JSON.stringify({context,elements,tables});
