window.__ModuleLoader__.load({
  id: '@local/pdf-reading-mode',
  factory(require) {
    const React = require('react');
    const {useState, useEffect, useLayoutEffect, useRef} = React;
    const {flushSync} = require('react-dom');
    const h = React.createElement;
    const NS = 'pdf-reading-mode';
    const dictionaries = {
      zh: {paperRestartRequired:'删除功能的后台尚未更新，请彻底退出并重新打开 DeepSeek Harness。',deletePaper:'删除论文',undoDeletePaper:'撤销',paperRemoved:'论文已从列表移除',deletePaperHint:'从列表移除，保留 PDF、标注和对话',partialHighlight:'部分移除',openChatFolder:'打开会话记录目录',openWebChat:'在网页继续对话',dropCategory:'拖入 PDF 导入，或拖入库内论文移动到此分类',dropFiles:'拖入 PDF 导入到',dragPaper:'拖到分类以移动论文',deleteChat:'删除对话（原生历史会归档保留）',deleteCategory:'删除分类',deleteCategories:'删除选中分类',categorySelection:'⌘/Ctrl 点击多选，Shift 点击连续选择；右键删除',categoryDeleteHint:'论文会移入“未分类”',noChats:'点击“新建对话”开始',deleting:'正在删除…',chatRecovered:'已恢复工作区绑定，旧会话记录已保留。', promptLabel:'阅读提示词', applyPrompt:'填入输入框', promptLoading:'载入提示词…', preset_reading:'深入阅读', preset_none:'普通对话', preset_summary:'论文概要', preset_explain:'解释选文', preset_method:'方法解析', preset_critique:'批判性分析', libraryTab:'分类', searchPapers:'搜索论文', searchPlaceholder:'搜索全部论文…', searchEmpty:'没有匹配的论文', searchHint:'↑↓ 选择 · Enter 打开 · Esc 关闭', newChat:'新建对话', chooseChat:'切换对话', chatLoading:'正在打开论文对话…', chatEmpty:'选择论文后开始对话', untitledChat:'对话', chatRetry:'重试对话', searchShortcut:'搜索论文 ⌘K', mode:'PDF 阅读', exit:'返回工作区', papers:'论文分类', all:'全部论文', outline:'Outline', highlights:'高亮', import:'导入 PDF', category:'新建分类', categoryName:'分类名称', cancel:'取消', create:'创建', empty:'打开一篇论文，开始阅读', hint:'拖入 PDF，或从本机选择文件', select:'选择 PDF', noOutline:'这份 PDF 没有内置目录', noPaper:'选择论文后显示目录', noHighlight:'选中文字，按 ⌘E 高亮', saved:'高亮已保存', saving:'正在保存…', loading:'正在打开 PDF…', pageRendering:'正在绘制页面…', error:'操作失败', fit:'适合宽度', previous:'上一页', next:'下一页', zoomIn:'放大', zoomOut:'缩小', page:'页码', chat:'论文对话', chatHint:'选中原文后可发送到右侧对话', pinch:'双指捏合缩放 · ⌘F 查找 · ⌘E 高亮 · ⇧⌘E 发送 · ⌘Z 撤销', findPlaceholder:'在 PDF 中查找', findPrevious:'上一个', findNext:'下一个', finding:'查找中…', noMatch:'无结果', filter:'筛选论文', untitled:'未分类', remove:'移除高亮', move:'移动到分类', retry:'重试', importProgress:'正在导入…', failedSave:'高亮保存失败，请重试', selected:'已选原文', clear:'清除', unsupported:'文件必须是 PDF', local:'本地文献库', count:'篇论文', ready:'阅读模式', noSession:'当前没有会话，请返回工作区创建会话', draft:'引用已填入右侧输入框', unavailable:'对话输入框暂不可用', emptyCategory:'此分类暂无论文', undone:'已撤销', redone:'已重做', chatZoomReset:'恢复对话缩放 100%', chatZoomHint:'双指捏合缩放对话'},
      en: {paperRestartRequired:'The deletion service has not updated. Quit and reopen DeepSeek Harness.',deletePaper:'Remove paper',undoDeletePaper:'Undo',paperRemoved:'Paper removed from the list',deletePaperHint:'Remove from the list; keep the PDF, highlights and conversations',partialHighlight:'Partially removed',openChatFolder:'Open conversation records folder',openWebChat:'Continue on website',dropCategory:'Drop PDFs to import or library papers to move to this collection',dropFiles:'Drop PDFs to import into',dragPaper:'Drag to a collection to move this paper',deleteChat:'Delete conversation (archive native history)',deleteCategory:'Delete collection',deleteCategories:'Delete selected collections',categorySelection:'Cmd/Ctrl-click to select multiple; Shift-click for a range; right-click to delete',categoryDeleteHint:'Papers move to Unfiled',noChats:'Create a new conversation to begin',deleting:'Deleting…',chatRecovered:'Restored workspace binding; previous conversation records were retained.', promptLabel:'Reading prompt', applyPrompt:'Insert prompt', promptLoading:'Loading prompts…', preset_reading:'Detailed reading', preset_none:'Plain conversation', preset_summary:'Paper summary', preset_explain:'Explain passage', preset_method:'Method walkthrough', preset_critique:'Critical review', libraryTab:'Library', searchPapers:'Search papers', searchPlaceholder:'Search all papers…', searchEmpty:'No matching papers', searchHint:'↑↓ Select · Enter Open · Esc Close', newChat:'New conversation', chooseChat:'Switch conversation', chatLoading:'Opening paper conversation…', chatEmpty:'Select a paper to start a conversation', untitledChat:'Conversation', chatRetry:'Retry conversation', searchShortcut:'Search papers ⌘K', mode:'PDF Reading',exit:'Back to workspace',papers:'Paper collections',all:'All papers',outline:'Outline',highlights:'Highlights',import:'Import PDF',category:'New collection',categoryName:'Collection name',cancel:'Cancel',create:'Create',empty:'Open a paper to start reading',hint:'Drop a PDF here or choose a local file',select:'Choose PDF',noOutline:'This PDF has no embedded outline',noPaper:'Select a paper to see its outline',noHighlight:'Select text and press ⌘E to highlight',saved:'Highlight saved',saving:'Saving…',loading:'Opening PDF…',pageRendering:'Rendering page…',error:'Operation failed',fit:'Fit width',previous:'Previous page',next:'Next page',zoomIn:'Zoom in',zoomOut:'Zoom out',page:'Page',chat:'Paper conversation',chatHint:'Select a passage to send it to chat',pinch:'Pinch to zoom · ⌘F find · ⌘E highlight · ⇧⌘E send · ⌘Z undo', findPlaceholder:'Find in PDF', findPrevious:'Previous match', findNext:'Next match', finding:'Searching…', noMatch:'No matches',filter:'Filter papers',untitled:'Unfiled',remove:'Remove highlight',move:'Move to collection',retry:'Retry',importProgress:'Importing…',failedSave:'Could not save highlights. Retry.',selected:'Selected passage',clear:'Clear',unsupported:'Choose a PDF file',local:'Local library',count:'papers',ready:'Reading mode',noSession:'No active session. Return to the workspace to create one.',draft:'Quote added to the chat input',unavailable:'Chat input is unavailable',emptyCategory:'No papers in this collection',undone:'Undone',redone:'Redone',chatZoomReset:'Reset conversation zoom to 100%',chatZoomHint:'Pinch to zoom the conversation'}
    };
    const css = `
.pr-sidebar,.pr-workspace{box-sizing:border-box;color:var(--dsw-alias-label-primary);font:inherit;min-height:0;height:100%;}

.pr-sidebar *,.pr-workspace *{box-sizing:border-box}
.pr-sidebar{display:flex;flex-direction:column;background:var(--dsw-alias-bg-layer-1);padding:14px 14px 10px;gap:12px;overflow:hidden}

.pr-sidebar button,.pr-workspace button{font:inherit;color:inherit;cursor:pointer;border:1px solid transparent;background:transparent;border-radius:6px;padding:6px 9px;line-height:1.4}
.pr-sidebar button:hover,.pr-workspace button:hover{background:var(--dsw-alias-interactive-bg-hover)}
.pr-sidebar button:focus-visible,.pr-workspace button:focus-visible{outline:2px solid var(--dsw-alias-brand-primary);outline-offset:1px}
.pr-sidebar button:disabled,.pr-workspace button:disabled{opacity:.4;cursor:default}
.pr-sidebar .pr-back{font-size:12px;text-align:left;color:var(--dsw-alias-label-secondary);padding:6px 0}
.pr-title{display:flex;align-items:center;gap:9px;font-size:17px;font-weight:600;padding:7px 2px}
.pr-section-title{display:flex;align-items:center;justify-content:space-between;font-size:11px;letter-spacing:.06em;color:var(--dsw-alias-label-secondary);padding:6px 2px}
.pr-sidebar .pr-primary,.pr-workspace .pr-primary{background:var(--dsw-alias-button-primary-fill);color:var(--dsw-alias-label-primary-inverted);padding:8px 12px}
.pr-library{max-height:37%;overflow:auto;flex-shrink:1}
.pr-category{display:flex;gap:5px;align-items:center;width:100%;text-align:left;font-size:12px!important}
.pr-category small{margin-left:auto;color:var(--dsw-alias-label-secondary)}
.pr-category[aria-current=true],.pr-paper[aria-current=true]{background:var(--dsw-alias-interactive-bg-active)!important}
.pr-papers{max-height:200px;overflow:auto}
.pr-paper-row{display:flex;align-items:center;min-width:0}.pr-paper-row .pr-paper{flex:1;min-width:0}.pr-paper-row .pr-paper-delete{flex:none;padding:4px 7px;color:var(--dsw-alias-label-secondary);font-size:15px}.pr-paper-row .pr-paper-delete:hover{color:var(--dsw-alias-state-error-primary)}
.pr-paper{display:block;width:100%;text-align:left;font-size:12px!important;padding:7px 8px 7px 19px!important;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.pr-tabs{display:flex;gap:14px;border-bottom:1px solid var(--dsw-alias-border-l1);margin-top:5px}
.pr-tabs button{border-radius:0!important;padding:8px 0!important;font-size:12px!important;color:var(--dsw-alias-label-secondary)}
.pr-tabs button[aria-selected=true]{border-bottom:2px solid var(--dsw-alias-brand-primary);color:var(--dsw-alias-label-primary)}
.pr-outline{flex:1;min-height:80px;overflow:auto}
.pr-outline button{display:block;width:100%;text-align:left;font-size:12px;line-height:1.5;margin:2px 0}
.pr-muted{font-size:12px;color:var(--dsw-alias-label-secondary);line-height:1.7;padding:10px 2px}
.pr-highlight-item{border-bottom:1px solid var(--dsw-alias-border-l1);padding:7px 0}
.pr-highlight-item button{font-size:12px}
.pr-sidebar footer{font-size:10px;color:var(--dsw-alias-label-secondary);padding:8px 0 0;border-top:1px solid var(--dsw-alias-border-l1)}

.pr-workspace{display:grid;grid-template-columns:minmax(280px,1fr) 5px minmax(310px,36%);overflow:hidden;background:var(--dsw-alias-bg-base);width:100%}
.pr-reader{display:flex;flex-direction:column;min-width:0;min-height:0;position:relative}
.pr-toolbar{height:49px;flex:none;display:flex;align-items:center;gap:4px;padding:5px 12px;border-bottom:1px solid var(--dsw-alias-border-l1);background:var(--dsw-alias-bg-base);font-size:12px}
.pr-toolbar .pr-name{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex:1;min-width:30px;font-weight:500}
.pr-toolbar input{width:43px;text-align:center}
.pr-toolbar input,.pr-sidebar input,.pr-toolbar select{color:inherit;border:1px solid var(--dsw-alias-border-l1);background:var(--dsw-alias-bg-layer-1);border-radius:5px;padding:5px;font:inherit}
.pr-sidebar input{width:100%;font-size:12px}
.pr-scroll{flex:1;overflow:auto;position:relative;overscroll-behavior:contain;background:color-mix(in srgb,var(--dsw-alias-bg-base,#fff) 88%,#808080);--pr-paper-bg:#fff;touch-action:pan-x pan-y}
.pr-pages{padding:24px;min-width:100%;width:max-content;display:flex;flex-direction:column;align-items:center;gap:20px;position:relative;transform-origin:0 0}
.pr-page{position:relative;isolation:isolate;background:var(--pr-paper-bg,#fff);flex-shrink:0;box-shadow:0 0 0 1px rgb(0 0 0 / 8%),0 6px 22px rgb(0 0 0 / 14%);overflow:hidden}
.pr-page canvas{position:absolute;inset:0;width:100%;height:100%}
.pr-link-layer{position:absolute;inset:0;z-index:4;pointer-events:none}
.pr-pdf-link{position:absolute;pointer-events:auto;cursor:pointer;background:transparent}
.pr-pdf-link:focus-visible{outline:2px solid #3478f6;outline-offset:1px}
.pr-page-skeleton{position:absolute;inset:0;z-index:0;background:var(--dsw-alias-bg-skeleton);pointer-events:none;animation:pr-page-pulse 1.4s ease-in-out infinite}
@keyframes pr-page-pulse{0%,100%{opacity:.6}50%{opacity:1}}
@media (prefers-reduced-motion:reduce){.pr-page-skeleton{animation:none}}
.pr-page .textLayer{position:absolute;inset:0;overflow:clip;text-align:initial;line-height:1;text-size-adjust:none;forced-color-adjust:none;transform-origin:0 0;z-index:2;caret-color:CanvasText;--min-font-size:1;--text-scale-factor:calc(var(--total-scale-factor)*var(--min-font-size));--min-font-size-inv:calc(1/var(--min-font-size))}
.pr-page .textLayer :is(span,br){color:transparent;position:absolute;white-space:pre;cursor:text;transform-origin:0% 0%}
.pr-page .textLayer > :not(.markedContent),.pr-page .textLayer .markedContent span:not(.markedContent){z-index:1;font-size:calc(var(--text-scale-factor)*var(--font-height));--scale-x:1;--rotate:0deg;transform:rotate(var(--rotate)) scaleX(var(--scale-x)) scale(var(--min-font-size-inv))}
.pr-page .textLayer .markedContent{display:contents}
.pr-page .textLayer span::selection{background:var(--dsw-alias-bg-document-selection);color:transparent}
.pr-page .textLayer br::selection{background:transparent}
.pr-highlight-layer{position:absolute;inset:0;z-index:3;pointer-events:none;opacity:.62;mix-blend-mode:multiply}
.pr-hl{position:absolute;background:#ffdf4f}
.pr-find{position:absolute;background:color-mix(in srgb,var(--dsw-alias-state-warn-primary) 26%,transparent);border-radius:2px;pointer-events:none;z-index:4}
.pr-find[data-active=true]{background:color-mix(in srgb,var(--dsw-alias-state-warn-primary) 62%,transparent);box-shadow:0 0 0 1px var(--dsw-alias-state-warn-primary)}
.pr-find-bar{position:absolute;top:56px;right:16px;z-index:8;display:flex;align-items:center;gap:5px;padding:5px 7px;border:1px solid var(--dsw-alias-border-l1);border-radius:8px;background:var(--dsw-alias-bg-overlay);box-shadow:0 6px 20px color-mix(in srgb,var(--dsw-alias-label-primary) 14%,transparent);font-size:12px;color:var(--dsw-alias-label-primary)}
.pr-find-bar input{width:190px;border:1px solid var(--dsw-alias-border-l1);border-radius:5px;padding:4px 7px;background:var(--dsw-alias-bg-layer-1);color:inherit;font:inherit}
.pr-find-bar .pr-find-count{min-width:56px;text-align:center;color:var(--dsw-alias-label-secondary);font-variant-numeric:tabular-nums}
.pr-find-bar button{width:24px;height:24px;padding:0!important;display:grid;place-items:center;border:1px solid transparent}
.pr-find-bar button:hover{background:var(--dsw-alias-interactive-bg-hover)}
.pr-status{min-height:28px;padding:6px 12px;font-size:10px;color:var(--dsw-alias-label-secondary);border-top:1px solid var(--dsw-alias-border-l1);display:flex;justify-content:space-between;gap:10px}
.pr-empty{height:100%;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:14px;padding:30px;text-align:center}
.pr-empty h2{font-size:20px;font-weight:500;margin:0}
.pr-empty p{font-size:12px;color:var(--dsw-alias-label-secondary);margin:0}
.pr-empty svg{margin-bottom:10px;color:var(--dsw-alias-label-secondary)}
.pr-divider{cursor:col-resize;border-left:1px solid var(--dsw-alias-border-l1);background:var(--dsw-alias-bg-base);touch-action:none}
.pr-chat{min-width:0;min-height:0;display:flex;flex-direction:column;overflow:hidden;background:var(--dsw-alias-bg-base)}
.pr-chat-head{height:49px;flex:none;padding:15px 17px;border-bottom:1px solid var(--dsw-alias-border-l1);font-size:12px;font-weight:500}
.pr-native-chat{flex:1;min-height:0;display:flex;flex-direction:column;position:relative;overflow:hidden}
.pr-native-chat>div{min-height:0;flex:1}
.pr-error{padding:8px 12px;color:var(--dsw-alias-state-error-primary);font-size:12px;background:var(--dsw-alias-bg-layer-1)}
.pr-form{display:flex;gap:4px;padding:4px 0}
.pr-form input{min-width:0}
.pr-mini-label{font-size:10px;color:var(--dsw-alias-label-secondary)}

`;
    const refinedCss = `
.pr-sidebar{position:relative;padding:52px 12px 12px;gap:10px}
.pr-window-drag{position:absolute;inset:0 0 auto;height:42px}
.pr-window-drag,.pr-toolbar,.pr-chat-head{-webkit-app-region:drag}
.pr-toolbar :is(button,input,select,a),.pr-chat-head :is(button,input,select,a,[role=tab]){-webkit-app-region:no-drag}
.pr-sidebar button,.pr-sidebar input,.pr-tabs{-webkit-app-region:no-drag}
.pr-sidebar .pr-back{flex:none;align-self:flex-start;padding:5px 6px;line-height:18px;margin:0;min-height:28px}
.pr-title{font-size:16px;padding:2px 5px}
.pr-sidebar .pr-tabs{display:flex;flex:none;gap:0;margin:0;padding:0 0 1px}
.pr-tabs button{flex:1;white-space:nowrap;text-align:center;padding:8px 5px!important;font-size:12px!important;line-height:18px}
.pr-tab-panel{flex:1;min-height:0;overflow:auto;padding:5px 0}
.pr-sidebar .pr-library{max-height:none;overflow:visible}
.pr-sidebar .pr-papers{max-height:none;overflow:visible}
.pr-sidebar .pr-outline{min-height:0;flex:none;overflow:visible}
.pr-sidebar .pr-outline button{padding-top:3px;padding-bottom:3px;margin:0;line-height:1.35;font-size:12px;min-height:23px}
.pr-sidebar .pr-outline button:hover{background:var(--dsw-alias-interactive-bg-hover)}
.pr-paper[aria-current=true]{color:var(--dsw-alias-brand-primary)}
.pr-sidebar footer{margin-top:auto;flex:none;line-height:1.5}
.pr-sidebar-search{display:flex;align-items:center;justify-content:space-between;border:1px solid var(--dsw-alias-border-l1)!important;font-size:12px!important;color:var(--dsw-alias-label-secondary)!important}
.pr-sidebar-search kbd{font:inherit;font-size:10px}
.pr-scroll{overflow-anchor:none;scrollbar-gutter:stable}
.pr-pages,.pr-page{overflow-anchor:none}
.pr-pages{min-width:100%;will-change:auto}
.pr-text-root{position:absolute;inset:0 auto auto 0;transform-origin:0 0;z-index:2}
.pr-page .textLayer{--scale-factor:var(--pr-raster-scale);--total-scale-factor:var(--pr-raster-scale)}
.pr-chat-head{height:auto;min-height:49px;display:flex;align-items:center;justify-content:space-between;gap:8px;padding:9px 12px}
.pr-chat-head-title{flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.pr-chat-controls{display:flex;align-items:center;gap:5px;min-width:0;max-width:80%}
.pr-chat-controls select{min-width:0;max-width:280px;flex:1;background:var(--dsw-alias-bg-layer-1);color:inherit;border:1px solid var(--dsw-alias-border-l1);border-radius:6px;padding:5px 7px;font:inherit;font-size:12px}
.pr-chat-head button{font-size:12px;white-space:nowrap}
.pr-chat-placeholder{padding:24px;font-size:12px;color:var(--dsw-alias-label-secondary);line-height:1.7}
.pr-toolbar{gap:3px}
.pr-toolbar select{max-width:130px}
.pr-toolbar .pr-name{font-size:12px}
.pr-chat-prompt{display:flex;align-items:center;gap:7px;padding:7px 12px;border-bottom:1px solid var(--dsw-alias-border-l1);font-size:11px;flex:none}
.pr-chat-prompt label{color:var(--dsw-alias-label-secondary);white-space:nowrap}
.pr-chat-prompt select{flex:1;min-width:0;padding:5px;background:var(--dsw-alias-bg-layer-1);border:1px solid var(--dsw-alias-border-l1);border-radius:5px;color:inherit;font:inherit}
.pr-chat-prompt button{font-size:11px;white-space:nowrap}
.pr-chat-prompt .pr-record-action{display:grid;place-items:center;flex:none;width:26px;height:25px;padding:0;border:1px solid var(--dsw-alias-border-l1);border-radius:5px;font-size:16px;color:inherit;text-decoration:none}
.pr-chat-head{padding:0 8px;gap:6px;flex:none}
.pr-chat-head>button{flex:none;font-size:12px;white-space:nowrap}
.pr-conversation-tabs{display:flex;align-items:stretch;align-self:stretch;flex:1;min-width:0;gap:3px;overflow-x:auto;overflow-y:hidden;scrollbar-width:thin}
.pr-conversation-tabs>button{flex:0 0 auto;max-width:200px;min-width:68px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;border-radius:0;padding:10px 12px;border-bottom:2px solid transparent;font-size:12px;color:var(--dsw-alias-label-secondary)}
.pr-conversation-tabs>button[aria-selected=true]{border-bottom-color:var(--dsw-alias-brand-primary);color:var(--dsw-alias-label-primary);background:var(--dsw-alias-interactive-bg-hover)}
.pr-native-chat [data-composer-seat]{margin-top:auto}
.pr-zoom-chip{flex:none;height:22px;padding:0 6px;border:1px solid var(--dsw-alias-border-l1);border-radius:5px;font-size:11px!important;line-height:1;color:var(--dsw-alias-label-secondary)}
.pr-zoom-chip:hover{color:var(--dsw-alias-label-primary)}
.pr-search-catcher{position:fixed;inset:0;z-index:70;display:flex;justify-content:center;align-items:flex-start;padding-top:14vh;background:color-mix(in srgb,var(--dsw-alias-label-primary) 12%,transparent);-webkit-app-region:no-drag}
.pr-search-dialog{width:min(650px,calc(100vw - 48px));max-height:65vh;display:flex;flex-direction:column;overflow:hidden;border:1px solid var(--dsw-alias-border-l1);border-radius:12px;background:var(--dsw-alias-bg-overlay);box-shadow:0 14px 48px color-mix(in srgb,var(--dsw-alias-label-primary) 20%,transparent);color:var(--dsw-alias-label-primary);font:inherit}
.pr-search-head{display:flex;align-items:center;gap:10px;padding:15px 16px;border-bottom:1px solid var(--dsw-alias-border-l1)}
.pr-search-head input{flex:1;min-width:0;border:0;outline:0;color:inherit;background:transparent;font:inherit;font-size:16px}
.pr-search-head button{border:1px solid var(--dsw-alias-border-l1);border-radius:4px;padding:3px 6px;background:transparent;color:var(--dsw-alias-label-secondary);font:inherit;font-size:11px;cursor:pointer}
.pr-search-results{padding:6px;overflow:auto;min-height:70px}
.pr-search-result{display:flex;gap:12px;align-items:center;width:100%;padding:11px 12px;border:0;background:transparent;color:inherit;border-radius:6px;text-align:left;font:inherit;cursor:pointer}
.pr-search-result[aria-selected=true]{background:var(--dsw-alias-interactive-bg-hover)}
.pr-search-result span{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:13px}
.pr-search-result small{font-size:11px;color:var(--dsw-alias-label-secondary)}
.pr-search-footer{padding:9px 16px;border-top:1px solid var(--dsw-alias-border-l1);font-size:11px;color:var(--dsw-alias-label-secondary)}
.pr-search-empty{padding:20px;text-align:center;font-size:13px;color:var(--dsw-alias-label-secondary)}


.pr-sidebar button.pr-import{display:flex;align-items:center;justify-content:center;flex:none;width:100%;height:30px;min-height:30px;padding:5px 10px;font-size:12px!important;line-height:18px;white-space:nowrap;transition:none}
.pr-sidebar button.pr-import:hover,.pr-sidebar button.pr-import:active{background:var(--dsw-alias-button-primary-fill)!important;color:var(--dsw-alias-label-primary-inverted)!important;border-color:transparent;box-shadow:none;transform:none;filter:none}
.pr-sidebar .pr-form{display:flex;flex-flow:row nowrap;align-items:center;gap:6px;width:100%;padding:3px 0}
.pr-sidebar .pr-form input{flex:1;min-width:0;width:0;height:28px;padding:4px 8px;font-size:12px;line-height:18px}
.pr-sidebar .pr-form button{flex:none;min-width:44px;white-space:nowrap;padding:4px 8px;font-size:12px;line-height:18px}
.pr-drop-hint{font-size:10px;line-height:1.4;color:var(--dsw-alias-label-secondary);padding:0 3px 5px}
.pr-sidebar [data-drop-active=true]{outline:1px dashed var(--dsw-alias-brand-primary);outline-offset:-1px;background:var(--dsw-alias-interactive-bg-hover)!important;border-radius:6px}
.pr-papers{min-height:35px}
.pr-category[aria-selected=true]{background:var(--dsw-alias-interactive-bg-active)!important}
.pr-category-menu{position:fixed;z-index:2000;width:190px;max-width:calc(100vw - 16px);padding:4px;border:1px solid var(--dsw-alias-border-l1);border-radius:7px;background:var(--dsw-alias-bg-base);box-shadow:0 4px 16px color-mix(in srgb,var(--dsw-alias-label-primary) 12%,transparent);-webkit-app-region:no-drag}
.pr-category-menu button{width:100%;text-align:left;white-space:nowrap;font-size:12px;padding:6px 8px}
.pr-category-menu small{display:block;padding:3px 8px 5px;font-size:11px;color:var(--dsw-alias-label-secondary)}
.pr-conversation-tab{display:flex;flex:none;align-items:center;max-width:220px;min-width:88px;border-bottom:2px solid transparent}
.pr-conversation-tab>button[role=tab]{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;padding:10px 8px;border-radius:0;font-size:12px;color:var(--dsw-alias-label-secondary)}
.pr-conversation-tab[data-selected=true]{border-bottom-color:var(--dsw-alias-brand-primary);background:var(--dsw-alias-interactive-bg-hover)}
.pr-conversation-tab[data-selected=true]>button[role=tab]{color:var(--dsw-alias-label-primary);font-weight:600}
.pr-conversation-tab .pr-tab-close{display:flex;flex:none;align-items:center;justify-content:center;width:22px;height:22px;margin-right:3px;padding:0;font-size:14px;line-height:1;color:var(--dsw-alias-label-secondary)}
`;
    function Icon({size=22}) {return h('svg',{width:size,height:size,viewBox:'0 0 24 24',fill:'none',stroke:'currentColor',strokeWidth:1.5,'aria-hidden':true},h('path',{d:'M6 3h8l4 4v14H6z M14 3v5h4 M9 12h6 M9 16h6'}));}
    async function api(path, data, signal) {const response=await fetch('/pdf-reading/'+path,{method:data===undefined?'GET':'POST',headers:data===undefined?undefined:{'Content-Type':'application/json'},body:data===undefined?undefined:JSON.stringify(data),signal});const result=await response.json();if(!response.ok)throw new Error(result.error||result.message||String(response.status));return result;}
    const PAPER_DRAG_TYPE='application/x-dsh-paper-id';
    function dragKind(transfer){
      const types=Array.from(transfer?.types||[]);
      return types.includes(PAPER_DRAG_TYPE)?'paper':types.includes('Files')||transfer?.files?.length?'files':null;
    }
    function stopDrop(event){event.preventDefault();event.stopPropagation();}
    function blockFileNavigation(event){if(dragKind(event.dataTransfer)){stopDrop(event);if(event.type==='dragover')event.dataTransfer.dropEffect='none';}}
    function primaryModifier(event){
      const mac=typeof navigator!=='undefined'&&/Mac|iPhone|iPad/i.test(navigator.platform||navigator.userAgent||'');
      return mac?event.metaKey:event.ctrlKey;
    }
    function editableTarget(target){return !!target&&(target.isContentEditable===true||/^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName||''));}
    function buildPageIndex(pdfjs,viewport,content){
      let text='';const spans=[];
      for(const item of content.items){
        if(typeof item.str!=='string'||!item.str.length)continue;
        const start=text.length;text+=item.str;
        const tx=pdfjs.Util.transform(viewport.transform,item.transform);
        const height=Math.hypot(tx[2],tx[3])||Math.hypot(item.transform[2],item.transform[3])||10;
        spans.push({start,end:text.length,x:tx[4],y:tx[5]-height,width:item.width,height});
      }
      return {text,spans,width:viewport.width||1,height:viewport.height||1};
    }
    function matchRects(index,start,end){
      const rects=[];
      for(const span of index.spans){
        if(span.end<=start||span.start>=end)continue;
        const length=span.end-span.start,from=Math.max(start,span.start)-span.start,to=Math.min(end,span.end)-span.start;
        rects.push({x:(span.x+span.width*(from/length))/index.width,y:span.y/index.height,width:span.width*((to-from)/length)/index.width,height:span.height/index.height});
      }
      return rects;
    }
    function alignTextLayer(textLayer,content,viewport,root){
      if(viewport.rotation!==0)return;
      const items=content.items.filter(item=>typeof item.str==='string');
      const displayScale=root.getBoundingClientRect().width/viewport.width;
      if(!Number.isFinite(displayScale)||displayScale<=0)return;
      const updates=[];
      items.forEach((item,index)=>{
        const span=textLayer.textDivs[index],matrix=item.transform;
        if(!span?.isConnected||!item.str.trim()||!Array.isArray(matrix)||Math.abs(matrix[1])>1e-6||Math.abs(matrix[2])>1e-6)return;
        const current=span.getBoundingClientRect().width,target=item.width*viewport.scale*(viewport.userUnit||1)*displayScale;
        const existing=parseFloat(span.style.getPropertyValue('--scale-x'))||1;
        const correction=target/current;
        if(Number.isFinite(correction)&&correction>.5&&correction<2)updates.push([span,existing*correction]);
      });
      for(const [span,scale] of updates)span.style.setProperty('--scale-x',String(scale));
    }
    function pdfLinkRegions(annotations,viewport){
      return annotations.flatMap(annotation=>{
        if(annotation.subtype!=='Link'||!Array.isArray(annotation.rect)||(!annotation.dest&&!annotation.url))return [];
        let url;
        if(annotation.url){try{const parsed=new URL(annotation.url);if(!['https:','http:','mailto:'].includes(parsed.protocol))return [];url=parsed.href;}catch{return [];}}
        const [x1,y1]=viewport.convertToViewportPoint(annotation.rect[0],annotation.rect[1]),[x2,y2]=viewport.convertToViewportPoint(annotation.rect[2],annotation.rect[3]);
        const left=Math.max(0,Math.min(x1,x2)),top=Math.max(0,Math.min(y1,y2)),right=Math.min(viewport.width,Math.max(x1,x2)),bottom=Math.min(viewport.height,Math.max(y1,y2));
        if(![left,top,right,bottom].every(Number.isFinite)||right<=left||bottom<=top)return [];
        return [{id:annotation.id,url,dest:annotation.dest,left:left/viewport.width,top:top/viewport.height,width:(right-left)/viewport.width,height:(bottom-top)/viewport.height}];
      });
    }
    async function resolvePdfDestination(pdf,destination){
      const target=typeof destination==='string'?await pdf.getDestination(destination):destination;
      if(!Array.isArray(target)||!target.length)return null;
      const page=typeof target[0]==='number'?target[0]+1:await pdf.getPageIndex(target[0])+1;
      if(!Number.isInteger(page)||page<1||page>pdf.numPages)return null;
      let offset=0;const kind=target[1]?.name,y=kind==='XYZ'?target[3]:kind==='FitH'||kind==='FitBH'?target[2]:kind==='FitR'?target[5]:null;
      if(typeof y==='number'&&Number.isFinite(y)){const destPage=await pdf.getPage(page),viewport=destPage.getViewport({scale:1});const point=viewport.convertToViewportPoint(0,y);offset=Math.max(0,Math.min(1,point[1]/viewport.height));}
      return {page,offset};
    }
    function eraseHighlightSelection(annotations,selectionRects){
      let changed=false;
      const result=[];
      for(const annotation of annotations){
        let removed=false;
        const rects=[];
        for(const rect of annotation.rects){
          let pieces=[rect];
          for(const selection of selectionRects){
            if(rect.page!==selection.page)continue;
            const overlapY=Math.min(rect.y+rect.height,selection.y+selection.height)-Math.max(rect.y,selection.y);
            if(overlapY<Math.min(rect.height,selection.height)*.5)continue;
            const next=[];
            for(const piece of pieces){
              const left=Math.max(piece.x,selection.x),right=Math.min(piece.x+piece.width,selection.x+selection.width);
              if(right-left<=1e-7){next.push(piece);continue;}
              removed=true;
              if(left-piece.x>1e-7)next.push({...piece,width:left-piece.x});
              if(piece.x+piece.width-right>1e-7)next.push({...piece,x:right,width:piece.x+piece.width-right});
            }
            pieces=next;
          }
          rects.push(...pieces);
        }
        if(!removed){result.push(annotation);continue;}
        changed=true;
        if(rects.length)result.push({...annotation,page:rects[0].page,rects,partial:true});
      }
      return {changed,annotations:result};
    }
    function paperLabel(name) {
      const text=typeof name==='string'?name.trim():'';
      const match=/^.+?\s-\s\d{4}\s-\s(.+)$/.exec(text);
      if(!match)return text;
      return match[1].replace(/\.pdf$/i,'').trim()||text;
    }
    function createModel() {
      let state = {papers:[],categories:[],selected:null,category:null,categorySelection:[],tab:'papers',outline:[],page:1,pages:0,annotations:[],error:'',busy:false,notice:'',jump:null,searchOpen:false,conversations:[],chatSessionId:null,chatBusy:false,chatClosedEmpty:false,chatError:'',chatRecord:null,chatRecordError:'',pendingQuote:null,promptPresets:[],promptPreset:'reading',promptBusy:false,promptError:''};
      const listeners = new Set();
      const source = {getSnapshot:()=>state,subscribe(fn){listeners.add(fn);return()=>listeners.delete(fn);}};
      const patch = value => {state={...state,...value};listeners.forEach(fn=>fn());};
      let chatRevision=0;
      async function openChat(action='ensure',sessionId) {
        const paperId=state.selected;
        if(!paperId)return;
        const revision=++chatRevision;
        patch({chatBusy:true,chatError:'',chatRecovery:'',pendingQuote:null});
        try {
          const group=await api('conversation',{paperId,action,...(sessionId?{sessionId}:{})});
          if(revision!==chatRevision||state.selected!==paperId)return;
          patch({conversations:group.conversations,chatSessionId:group.sessionId,chatClosedEmpty:action==='delete'&&!group.sessionId,chatBusy:false,chatRecovery:group.recoveryNotice||'',chatRecord:null,chatRecordError:group.archiveNotice||''});
        } catch(error) {
          if(revision===chatRevision&&state.selected===paperId)patch({chatBusy:false,chatError:error.message});
        }
      }
      const select=id=>{
        if(id===state.selected){patch({searchOpen:false});return;}
        const paper=state.papers.find(p=>p.id===id);if(!paper)return;
        patch({selected:id,annotations:paper.annotations||[],outline:[],pages:0,page:1,jump:null,error:'',notice:'',searchOpen:false,conversations:[],chatSessionId:null,chatClosedEmpty:false,pendingQuote:null});
        try{localStorage.setItem('pr.last',id);}catch(error){/* View preferences are optional. */}
        void openChat();
      };
      async function load(){
        try{
          const lib=await api('library');let id=state.selected;
          try{id=id||localStorage.getItem('pr.last');}catch(error){/* View preferences are optional. */}
          const paper=lib.papers.find(p=>p.id===id)||lib.papers[0];
          const changed=paper?.id!==state.selected;
          patch({...lib,selected:paper?.id||null,annotations:paper?.annotations||[],error:''});
          if(paper&&(changed||(!state.chatSessionId&&!state.chatClosedEmpty)))void openChat();
          if(!state.promptPresets.length)void api('prompts').then(result=>patch({promptPresets:result.presets,promptPreset:result.defaultPreset,promptError:''})).catch(error=>patch({promptError:error.message}));
        }catch(error){patch({error:error.message});}
      }
      async function importFiles(files,options={}){
        const category=options.category??state.category??'Uncategorized';
        files=Array.from(files);
        if(!files.length||state.busy)return;
        patch({busy:true,error:''});
        try{for(const file of files){
          if(!file.name.toLowerCase().endsWith('.pdf'))throw new Error('PDF required');
          const bytes=new Uint8Array(await file.arrayBuffer());let binary='';
          for(let i=0;i<bytes.length;i+=32768)binary+=String.fromCharCode(...bytes.subarray(i,i+32768));
          const paper=await api('import',{name:file.name,data:btoa(binary),category});
          await load();select(paper.id);
        }}catch(error){patch({error:error.message});}finally{patch({busy:false});}
      }
      async function movePaper(id,category){
        if(!state.papers.some(paper=>paper.id===id)||!state.categories.includes(category))return;
        try{await api('move',{id,category});await load();}catch(error){patch({error:error.message});}
      }
      async function deletePaper(id){
        if(!state.papers.some(paper=>paper.id===id))throw new Error('Paper not found');
        await saves;
        const result=await api('papers/delete',{id}),wasSelected=state.selected===id;
        if(wasSelected){
          chatRevision++;
          patch({papers:state.papers.filter(paper=>paper.id!==id),selected:null,annotations:[],outline:[],pages:0,page:1,jump:null,conversations:[],chatSessionId:null,chatBusy:false,chatClosedEmpty:false,pendingQuote:null});
        }else patch({papers:state.papers.filter(paper=>paper.id!==id)});
        await load();return {...result,wasSelected,selectedAfter:state.selected};
      }
      async function restorePaper(removed){
        const paper=await api('papers/restore',{removalId:removed.removalId});
        const restoreSelection=removed.wasSelected&&state.selected===removed.selectedAfter;
        await load();if(restoreSelection)select(paper.id);
      }
      let saves=Promise.resolve();
      const history=new Map();
      function historyEntry(id){let entry=history.get(id);if(!entry){entry={past:[],future:[]};history.set(id,entry);}return entry;}
      function paperAnnotations(id){return state.papers.find(paper=>paper.id===id)?.annotations||[];}
      function canUndo(){return !!(state.selected&&history.get(state.selected)?.past.length);}
      function canRedo(){return !!(state.selected&&history.get(state.selected)?.future.length);}
      function undo(){const id=state.selected,entry=id?history.get(id):null;if(!entry?.past.length)return Promise.resolve();entry.future.push(paperAnnotations(id));return commit(entry.past.pop(),id).then(()=>patch({notice:'undone'}));}
      function redo(){const id=state.selected,entry=id?history.get(id):null;if(!entry?.future.length)return Promise.resolve();entry.past.push(paperAnnotations(id));return commit(entry.future.pop(),id).then(()=>patch({notice:'redone'}));}
      function save(annotations,id=state.selected){
        const entry=historyEntry(id);
        entry.past.push(paperAnnotations(id));if(entry.past.length>100)entry.past.shift();
        entry.future.length=0;
        return commit(annotations,id);
      }
      function commit(annotations,id=state.selected){
        patch({notice:'saving'});
        saves=saves.catch(()=>{}).then(async()=>{
          try{await api('annotations',{id,annotations});patch({papers:state.papers.map(p=>p.id===id?{...p,annotations}:p),...(state.selected===id?{annotations,notice:'saved',error:''}:{})});}
          catch(error){patch({error:error.message,notice:'failedSave'});throw error;}
        });return saves;
      }
      function deactivate(){chatRevision++;patch({searchOpen:false,pendingQuote:null,chatSessionId:null,chatBusy:false,notice:'',chatRecovery:'',chatError:'',promptError:''});}
      async function fillPrompt(selection,page){
        const paperId=state.selected,sessionId=state.chatSessionId,preset=state.promptPreset;
        if(!paperId||!sessionId||state.chatBusy)return;
        patch({promptBusy:true,promptError:''});
        try{
          const result=await api('prompt',{paperId,preset,...(preset==='reading'?{}:{selection:selection||undefined,page})});
          if(result.text.trim()&&state.selected===paperId&&state.chatSessionId===sessionId)patch({pendingQuote:{sessionId,text:result.text+(preset==='reading'?'':'\n\n'),preset,nonce:Date.now()}});
        }catch(error){patch({promptError:error.message});}finally{patch({promptBusy:false});}
      }
      async function refreshChatRecord(sessionId=state.chatSessionId){
        if(!sessionId)return;
        try{const record=await api('chat-info?sessionId='+encodeURIComponent(sessionId));if(state.chatSessionId===sessionId)patch({chatRecord:record,chatRecordError:''});}
        catch(error){if(state.chatSessionId===sessionId)patch({chatRecordError:error.message});}
      }
      async function openChatFolder(){
        const sessionId=state.chatSessionId;if(!sessionId)return;
        try{await api('chat-folder',{sessionId});patch({chatRecordError:''});}catch(error){patch({chatRecordError:error.message});}
      }
      return {source,patch,load,select,importFiles,movePaper,deletePaper,restorePaper,save,undo,redo,canUndo,canRedo,openChat,deactivate,fillPrompt,refreshChatRecord,openChatFolder};
    }
    function Sidebar(props) {
      const {t,model,exit}=props,state=props.useReading(s=>s);
      const [query,setQuery]=useState(''),[creating,setCreating]=useState(false),[name,setName]=useState('');
      const [menu,setMenu]=useState(null),[deleting,setDeleting]=useState(false),[dropTarget,setDropTarget]=useState(null),[removedPaper,setRemovedPaper]=useState(null),[removingPaper,setRemovingPaper]=useState(false);
      const input=useRef(null),categoryList=useRef(null),anchor=useRef(null),menuRef=useRef(null),allButton=useRef(null);
      const selected=state.categorySelection||(state.category?[state.category]:[]);
      const categoryLabel=category=>category==='Uncategorized'?t('untitled'):category;
      const importCategory=selected.length===1?selected[0]:'Uncategorized';
      function dropProps(category){
        const target=category||importCategory,key=category||'papers';
        return {
          'data-drop-active':dropTarget===key,
          onDragOver:event=>{
            const kind=dragKind(event.dataTransfer);if(!kind)return;
            stopDrop(event);
            const accepted=!state.busy&&(kind==='files'||!!category);
            event.dataTransfer.dropEffect=accepted?(kind==='paper'?'move':'copy'):'none';
            setDropTarget(accepted?key:null);
          },
          onDragLeave:event=>{if(!event.currentTarget.contains(event.relatedTarget))setDropTarget(null);},
          onDrop:event=>{
            const kind=dragKind(event.dataTransfer);if(!kind)return;
            stopDrop(event);setDropTarget(null);
            if(state.busy)return;
            if(kind==='paper'){
              const id=event.dataTransfer.getData(PAPER_DRAG_TYPE);
              if(category&&state.papers.some(paper=>paper.id===id))return model.movePaper(id,category);
              return;
            }
            const files=Array.from(event.dataTransfer.files||[]);if(!files.length)return;
            setQuery('');model.patch({category:target,categorySelection:[target]});
            return model.importFiles(files,{category:target});
          }
        };
      }
      function selectCategory(category,event={}){
        let next;
        if(event.shiftKey&&anchor.current&&state.categories.includes(anchor.current)){
          const start=state.categories.indexOf(anchor.current),end=state.categories.indexOf(category);
          const range=state.categories.slice(Math.min(start,end),Math.max(start,end)+1);
          next=event.metaKey||event.ctrlKey?[...new Set([...selected,...range])]:range;
        }else if(event.metaKey||event.ctrlKey){next=selected.includes(category)?selected.filter(value=>value!==category):[...selected,category];}
        else next=[category];
        if(!event.shiftKey)anchor.current=category;
        model.patch({categorySelection:next,category:next.length===1?next[0]:null});
      }
      function openCategoryMenu(category,event){
        event.preventDefault();event.stopPropagation();
        const next=selected.includes(category)?selected:[category];
        model.patch({categorySelection:next,category:next.length===1?next[0]:null});
        const box=categoryList.current?.getBoundingClientRect();
        setMenu({x:Math.max(box?.left||8,Math.min(event.clientX,(box?.right||window.innerWidth)-190)),y:Math.max(8,Math.min(event.clientY,window.innerHeight-100)),categories:next.filter(value=>value!=='Uncategorized')});
      }
      function categoryKey(category,event){
        const index=state.categories.indexOf(category);
        if((event.metaKey||event.ctrlKey)&&event.key.toLowerCase()==='a'){
          event.preventDefault();model.patch({categorySelection:[...state.categories],category:null});return;
        }
        if(!['ArrowDown','ArrowUp','Home','End',' '].includes(event.key))return;
        event.preventDefault();
        const next=event.key==='Home'?0:event.key==='End'?state.categories.length-1:event.key==='ArrowDown'?Math.min(index+1,state.categories.length-1):event.key==='ArrowUp'?Math.max(0,index-1):index;
        selectCategory(state.categories[next],event);
        categoryList.current?.querySelectorAll('[role=option]')[next]?.focus();
      }
      useEffect(()=>{
        if(!menu)return;
        const outside=event=>{if(!menuRef.current?.contains(event.target))setMenu(null);};
        const escape=event=>{if(event.key==='Escape'){event.preventDefault();event.stopPropagation();setMenu(null);}};
        document.addEventListener('pointerdown',outside,true);document.addEventListener('keydown',escape,true);
        return()=>{document.removeEventListener('pointerdown',outside,true);document.removeEventListener('keydown',escape,true);};
      },[menu]);
      async function removeCategories(){
        if(!menu?.categories.length||deleting)return;
        setDeleting(true);
        try{
          await api('categories/delete',{categories:menu.categories});
          const current=model.source.getSnapshot();
          const remaining=(current.categorySelection||[]).filter(value=>!menu.categories.includes(value));
          model.patch({categorySelection:remaining,category:remaining.length===1?remaining[0]:null});
          await model.load();setMenu(null);allButton.current?.focus();
        }catch(error){model.patch({error:error.message});}finally{setDeleting(false);}
      }
      if(props.collapsed)return h('aside',{className:'pr-sidebar',onDragOver:blockFileNavigation,onDrop:blockFileNavigation},h('style',null,css+refinedCss),h('div',{className:'pr-window-drag','data-window-drag':true}),h('button',{onClick:exit,title:t('exit')},'←'),h('button',{onClick:()=>model.patch({searchOpen:true}),title:t('searchPapers')},h(Icon,{})));
      const papers=state.papers.filter(p=>(!selected.length||selected.includes(p.category))&&(p.title+' '+paperLabel(p.title)).toLowerCase().includes(query.toLowerCase()));
      const library=h(React.Fragment,null,
        h('div',{className:'pr-section-title'},t('papers'),h('button',{title:t('category'),onClick:()=>setCreating(!creating)},'+')),
        creating&&h('form',{className:'pr-form',onSubmit:async event=>{
          event.preventDefault();if(!name.trim())return;
          try{await api('category',{name:name.trim()});await model.load();setCreating(false);setName('');}catch(error){model.patch({error:error.message});}
        }},h('input',{value:name,onChange:e=>setName(e.target.value),placeholder:t('categoryName'),'aria-label':t('categoryName'),autoFocus:true,required:true}),h('button',{type:'submit'},t('create'))),
        h('div',{className:'pr-library'},
          h('button',{ref:allButton,className:'pr-category','aria-current':!selected.length,onClick:()=>{anchor.current=null;model.patch({categorySelection:[],category:null});}},'▱ '+t('all'),h('small',null,state.papers.length)),
          h('div',{ref:categoryList,className:'pr-category-list',role:'listbox','aria-label':t('papers'),'aria-multiselectable':true,title:t('categorySelection')},...state.categories.map(category=>h('button',{key:category,role:'option',className:'pr-category','data-category':category,...dropProps(category),title:t('dropCategory'),'aria-label':categoryLabel(category)+' · '+t('dropCategory'),'aria-selected':selected.includes(category),onClick:event=>selectCategory(category,event),onContextMenu:event=>openCategoryMenu(category,event),onKeyDown:event=>categoryKey(category,event)},'▱ '+categoryLabel(category),h('small',null,state.papers.filter(p=>p.category===category).length))))),
        h('input',{...dropProps(),value:query,placeholder:t('filter'),'aria-label':t('filter'),'aria-description':t('dropFiles')+' '+categoryLabel(importCategory),onChange:e=>setQuery(e.target.value),style:{margin:'9px 0'}}),
        h('small',{className:'pr-drop-hint'},t('dropFiles')+' '+categoryLabel(importCategory)),
        h('div',{...dropProps(),className:'pr-papers',role:'region','aria-label':t('dropFiles')+' '+categoryLabel(importCategory)},...papers.map(p=>h('div',{key:p.id,className:'pr-paper-row'},h('button',{className:'pr-paper',title:p.title,draggable:true,'aria-description':t('dragPaper'),onDragStart:event=>{event.dataTransfer.effectAllowed='move';event.dataTransfer.setData(PAPER_DRAG_TYPE,p.id);},onDragEnd:()=>setDropTarget(null),'aria-current':p.id===state.selected,onClick:()=>model.select(p.id)},paperLabel(p.title)),h('button',{className:'pr-paper-delete',type:'button',disabled:removingPaper,title:t('deletePaperHint'),'aria-label':t('deletePaper')+'：'+paperLabel(p.title),onClick:async()=>{if(removingPaper)return;setRemovingPaper(true);try{setRemovedPaper(await model.deletePaper(p.id));}catch(error){model.patch({error:error.message==='Route not found'?t('paperRestartRequired'):error.message});}finally{setRemovingPaper(false);}}},'×'))),!papers.length&&h('p',{className:'pr-muted'},t('emptyCategory'))),removedPaper&&h('div',{className:'pr-paper-removed',role:'status'},t('paperRemoved'),' ',h('button',{type:'button',disabled:removingPaper,onClick:async()=>{if(removingPaper)return;setRemovingPaper(true);try{await model.restorePaper(removedPaper);setRemovedPaper(null);}catch(error){model.patch({error:error.message==='Route not found'?t('paperRestartRequired'):error.message});}finally{setRemovingPaper(false);}}},t('undoDeletePaper'))));
      const outline=h('div',{className:'pr-outline'},state.outline.length?state.outline.map((entry,i)=>h('button',{key:i,title:entry.title,style:{paddingLeft:7+entry.depth*10},onClick:()=>model.patch({jump:{page:entry.page,nonce:Date.now()}})},entry.title)):h('p',{className:'pr-muted'},t(state.selected?'noOutline':'noPaper')));
      const highlights=h('div',{className:'pr-outline'},state.annotations.length?state.annotations.map(annotation=>h('div',{key:annotation.id,className:'pr-highlight-item'},h('button',{onClick:()=>model.patch({jump:{page:annotation.page,nonce:Date.now()}})},h('span',{className:'pr-mini-label'},'p. '+annotation.page+(annotation.partial?' · '+t('partialHighlight'):'')),h('br'),annotation.text),h('button',{title:t('remove'),onClick:()=>model.save(state.annotations.filter(a=>a.id!==annotation.id)).catch(()=>{})},'×'))):h('p',{className:'pr-muted'},t('noHighlight')));
      return h('aside',{className:'pr-sidebar',onDragOver:blockFileNavigation,onDrop:blockFileNavigation},h('style',null,css+refinedCss),h('div',{className:'pr-window-drag','data-window-drag':true}),
        h('button',{className:'pr-back',onClick:exit},'← '+t('exit')),
        h('div',{className:'pr-title'},h(Icon,{}),t('mode')),
        h('button',{className:'pr-sidebar-search',onClick:()=>model.patch({searchOpen:true})},t('searchPapers'),h('kbd',null,'⌘K')),
        h('button',{className:'pr-primary pr-import',disabled:state.busy,onClick:()=>input.current.click()},'+ '+t(state.busy?'importProgress':'import')),
        h('input',{type:'file',accept:'.pdf,application/pdf',multiple:true,hidden:true,ref:input,onChange:e=>{model.importFiles(e.target.files);e.target.value='';}}),
        h('div',{className:'pr-tabs',role:'tablist'},...['papers','outline','highlights'].map(tab=>h('button',{key:tab,role:'tab','aria-selected':state.tab===tab,onClick:()=>model.patch({tab})},t(tab==='papers'?'libraryTab':tab)+(tab==='highlights'&&state.annotations.length?' · '+state.annotations.length:'')))),
        h('div',{className:'pr-tab-panel',role:'tabpanel','data-tab':state.tab},state.tab==='papers'?library:state.tab==='outline'?outline:highlights),
        h('footer',null,t('local')+' · '+state.papers.length+' '+t('count')),
        menu&&h('div',{ref:menuRef,className:'pr-category-menu',role:'menu','aria-label':t('deleteCategory'),style:{left:menu.x,top:menu.y},onContextMenu:event=>event.preventDefault()},h('button',{role:'menuitem',disabled:deleting||!menu.categories.length,onClick:removeCategories},t(deleting?'deleting':menu.categories.length>1?'deleteCategories':'deleteCategory')+(menu.categories.length>1?' · '+menu.categories.length:'')),h('small',null,t('categoryDeleteHint'))));
    }
    function PaperSearch(props){
      const {t,model}=props,state=props.useReading(s=>s),input=useRef(null),previousFocus=useRef(null);
      const [query,setQuery]=useState(''),[selected,setSelected]=useState(0);
      const needle=query.trim().toLocaleLowerCase();
      const matches=state.papers.filter(p=>!needle||`${p.title} ${paperLabel(p.title)} ${p.category}`.toLocaleLowerCase().includes(needle));
      function closeSearch(){model.patch({searchOpen:false});}
      function choose(paper){model.select(paper.id);closeSearch();}
      useEffect(()=>{
        if(!state.searchOpen)return;
        previousFocus.current=document.activeElement;setQuery('');setSelected(0);input.current?.focus();
        return()=>{const target=previousFocus.current;if(target instanceof HTMLElement&&target.isConnected)target.focus();};
      },[state.searchOpen]);
      useEffect(()=>setSelected(0),[query]);
      useEffect(()=>{
        if(!state.searchOpen)return;
        const key=event=>{
          if(event.isComposing)return;
          if(!['Escape','ArrowDown','ArrowUp','Enter','Tab'].includes(event.key)&&!(event.code==='KeyK'&&(event.metaKey||event.ctrlKey)))return;
          event.preventDefault();event.stopImmediatePropagation();
          if(event.key==='Escape'||event.code==='KeyK')closeSearch();
          else if(event.key==='ArrowDown')setSelected(value=>Math.min(value+1,Math.max(0,matches.length-1)));
          else if(event.key==='ArrowUp')setSelected(value=>Math.max(0,value-1));
          else if(event.key==='Enter'&&matches[selected])choose(matches[selected]);
          else if(event.key==='Tab')input.current?.focus();
        };
        window.addEventListener('keydown',key,true);return()=>window.removeEventListener('keydown',key,true);
      },[state.searchOpen,matches.map(p=>p.id).join(','),selected]);
      useEffect(()=>{if(state.searchOpen)document.querySelector('.pr-search-result[aria-selected=true]')?.scrollIntoView({block:'nearest'});},[selected,state.searchOpen]);
      if(!state.searchOpen)return null;
      return h('div',{className:'pr-search-catcher',onMouseDown:event=>{if(event.target===event.currentTarget)closeSearch();}},h('style',null,refinedCss),
        h('section',{className:'pr-search-dialog',role:'dialog','aria-modal':true,'aria-label':t('searchPapers'),'data-shortcut-modal':'pdf-reading-search'},
          h('div',{className:'pr-search-head'},h(Icon,{size:20}),h('input',{ref:input,value:query,onChange:e=>setQuery(e.target.value),placeholder:t('searchPlaceholder'),'aria-label':t('searchPapers'),'aria-controls':'pr-search-results','aria-activedescendant':matches[selected]?'pr-result-'+matches[selected].id:undefined,autoComplete:'off',spellCheck:false}),h('button',{onClick:closeSearch,'aria-label':t('cancel')},'Esc')),
          h('div',{className:'pr-search-results',id:'pr-search-results',role:'listbox'},matches.length?matches.map((paper,i)=>h('button',{key:paper.id,id:'pr-result-'+paper.id,className:'pr-search-result',role:'option','aria-selected':i===selected,onMouseEnter:()=>setSelected(i),onClick:()=>choose(paper)},h(Icon,{size:19}),h('span',null,paperLabel(paper.title)),h('small',null,paper.category==='Uncategorized'?t('untitled'):paper.category))):h('div',{className:'pr-search-empty'},t('searchEmpty'))),
          h('div',{className:'pr-search-footer'},t('searchHint'))));
    }
    function ConversationTabs({t,conversations,sessionRows,paperTitle,selected,busy,onSelect,onDelete}){
      const strip=useRef(null);
      useEffect(()=>{strip.current?.querySelector('[aria-selected=true]')?.scrollIntoView({block:'nearest',inline:'nearest'});},[selected]);
      function move(event,item){
        if(busy||!['ArrowRight','ArrowLeft','Home','End'].includes(event.key))return;
        const available=conversations.filter(value=>value.available);
        if(!available.length)return;
        event.preventDefault();
        const index=available.findIndex(value=>value.sessionId===item.sessionId);
        const next=event.key==='Home'?0:event.key==='End'?available.length-1:(index+(event.key==='ArrowRight'?1:-1)+available.length)%available.length;
        const target=available[next];onSelect(target.sessionId);
        strip.current?.querySelector('[data-session-id="'+target.sessionId+'"]')?.focus();
      }
      return h('div',{ref:strip,className:'pr-conversation-tabs',role:'tablist','aria-label':t('chooseChat')},...conversations.filter(item=>item.available).map((item,index)=>{
        const row=sessionRows[item.sessionId];
        const explicit=row?.projectionValues?.title;
        const label=paperLabel((explicit&&row?.displayTitle)||(row?.blank===false&&row?.displayTitle)||(item.title&&!/^Conversation \d+$/.test(item.title)?item.title:paperTitle)||t('untitledChat')+' '+(index+1));
        return h('span',{key:item.sessionId,className:'pr-conversation-tab',role:'presentation','data-selected':item.sessionId===selected},h('button',{id:'pr-chat-tab-'+item.sessionId,role:'tab','aria-selected':item.sessionId===selected,'aria-controls':'pr-chat-panel','data-session-id':item.sessionId,tabIndex:item.sessionId===selected?0:-1,disabled:busy||!item.available,title:item.available?label:item.unavailableReason,onClick:()=>onSelect(item.sessionId),onKeyDown:event=>move(event,item)},label),h('button',{className:'pr-tab-close',type:'button','aria-label':t('deleteChat')+'：'+label,title:t('deleteChat'),tabIndex:item.sessionId===selected?0:-1,disabled:busy||!!row?.running,onClick:event=>{event.stopPropagation();onDelete(item.sessionId);}},'×'));
      }));
    }
    function FixedChatView(props){return props.renderSlot('conversation.session',{view:'chat'});}
    function PaperChat(props){
      const {model,t}=props,state=props.useReading(s=>s);
      const session=props.useSession(s=>s),conversation=props.useConversation(s=>s),input=props.useInput(s=>s);
      const summaryBlank=props.useSessions(s=>s.byId[props.sessionId]?.blank);
      const active=conversation.activeTargets.size>0||(!session.blank&&!session.awaitingFirstTurn)||session.running;
      useEffect(()=>{if(!session.running)void model.refreshChatRecord(props.sessionId);},[props.sessionId,session.running]);
      const settling=!active&&session.openState==='loading'&&summaryBlank!==true;
      const hero=!active&&(session.openState==='open'||summaryBlank===true);
      useEffect(()=>{
        const quote=state.pendingQuote;if(!quote||quote.sessionId!==props.sessionId)return;
        const current=input.draft||'';let draft=quote.text+current;
        if(quote.preset==='reading'){const base=quote.text.trimEnd();const rest=current.startsWith(base)?current.slice(base.length):undefined;const previous=rest!==undefined&&(/^\s*$/.test(rest)||/^\s*当前 PDF 页码：第 \d+ 页。\s*$/.test(rest));draft=previous?quote.text:quote.text+(current?'\n\n'+current:'');}
        props.inputActions.setDraft(draft);props.inputActions.persistDraft();
        model.patch({pendingQuote:null,notice:'draft'});
      },[state.pendingQuote,props.sessionId]);
      return props.renderFactorySlot('conversation.content',{variant:'embedded',phase:settling?'settling':'active',hero:false},{slots:{views:FixedChatView}});
    }
    const PAGE_BITMAP_BUDGET=24000000, PAGE_RENDER_PIXEL_LIMIT=32000000;
    function pageRenderRatio(viewport,pixelRatio){
      return Math.min(Math.max(1,pixelRatio||1),Math.sqrt(PAGE_RENDER_PIXEL_LIMIT/(viewport.width*viewport.height)));
    }
    const pageBitmapCache=new Map();
    let pageBitmapTick=0,pageBitmapScale=0;
    function pageBitmapTotal(){let total=0;for(const entry of pageBitmapCache.values())total+=entry.pixels;return total;}
    function dropPageBitmap(entry){
      if(!entry)return;
      if(entry.pixels>0&&entry.canvas){entry.canvas.style.visibility='hidden';entry.canvas.width=0;entry.canvas.height=0;}
      entry.pixels=0;
      if(pageBitmapCache.get(entry.number)===entry)pageBitmapCache.delete(entry.number);
      entry.onDrop?.();
    }
    function trimPageBitmapCache(){
      if(pageBitmapTotal()<=PAGE_BITMAP_BUDGET)return;
      const idle=[...pageBitmapCache.values()].filter(entry=>!entry.near).sort((a,b)=>a.used-b.used);
      for(const entry of idle){if(pageBitmapTotal()<=PAGE_BITMAP_BUDGET)return;dropPageBitmap(entry);}
    }
    function invalidatePageBitmaps(rasterScale){
      if(pageBitmapScale===rasterScale)return;
      pageBitmapScale=rasterScale;
      for(const entry of [...pageBitmapCache.values()])if(!entry.near&&entry.rasterScale!==rasterScale)dropPageBitmap(entry);
    }
    function PdfPage({pdf,pdfjs,number,baseViewport,scale,rasterScale,annotations,root,onFailure,onLink,label,find=[]}) {
      const ref=useRef(null),canvas=useRef(null),text=useRef(null),entry=useRef(null);
      const [near,setNear]=useState(false),[rendered,setRendered]=useState(false),[textScale,setTextScale]=useState(rasterScale),[bitmapVersion,setBitmapVersion]=useState(0),[links,setLinks]=useState([]);
      useEffect(()=>{const observer=new IntersectionObserver(entries=>{const isNear=entries[0].isIntersecting;if(entry.current){entry.current.near=isNear;entry.current.used=++pageBitmapTick;}setNear(isNear);},{root:root.current,rootMargin:'400px'});observer.observe(ref.current);return()=>observer.disconnect();},[pdf]);
      useEffect(()=>()=>{const value=entry.current;if(!value)return;entry.current=null;if(pageBitmapCache.get(value.number)===value)pageBitmapCache.delete(value.number);value.pixels=0;if(value.canvas){value.canvas.width=0;value.canvas.height=0;}},[]);
      useEffect(()=>{if(!near){setLinks([]);return;}let cancelled=false;(async()=>{const page=await pdf.getPage(number);const values=await page.getAnnotations({intent:'display'});if(!cancelled)setLinks(pdfLinkRegions(values,baseViewport));})().catch(error=>{if(!cancelled)onFailure(error.message);});return()=>{cancelled=true;};},[pdf,near,number,baseViewport]);
      useEffect(()=>{
        const current=entry.current;
        if(!near){
          if(current){current.near=false;current.used=++pageBitmapTick;}
          text.current?.replaceChildren();
          trimPageBitmapCache();
          return;
        }
        if(current&&current.pixels>0){current.near=true;current.used=++pageBitmapTick;}
        invalidatePageBitmaps(rasterScale);
        let cancelled=false,renderTask,textLayer;
        (async()=>{
          const page=await pdf.getPage(number);if(cancelled)return;
          const viewport=page.getViewport({scale:rasterScale});
          const ratio=pageRenderRatio(viewport,devicePixelRatio);
          const next=document.createElement('canvas');next.width=Math.ceil(viewport.width*ratio);next.height=Math.ceil(viewport.height*ratio);
          renderTask=page.render({canvasContext:next.getContext('2d',{alpha:false}),viewport,transform:ratio!==1?[ratio,0,0,ratio,0,0]:undefined});
          await renderTask.promise;if(cancelled)return;
          const content=await page.getTextContent();if(cancelled)return;
          const layer=document.createElement('div');layer.className='textLayer';layer.style.setProperty('--pr-raster-scale',rasterScale);
          textLayer=new pdfjs.TextLayer({textContentSource:content,container:layer,viewport});await textLayer.render();if(cancelled)return;
          canvas.current.width=next.width;canvas.current.height=next.height;canvas.current.getContext('2d',{alpha:false}).drawImage(next,0,0);
          canvas.current.style.visibility='visible';
          next.width=0;next.height=0;
          text.current.replaceChildren(layer);flushSync(()=>setTextScale(rasterScale));
          alignTextLayer(textLayer,content,viewport,text.current);
          const previous=pageBitmapCache.get(number);if(previous&&previous.canvas!==canvas.current)dropPageBitmap(previous);
          const value={number,canvas:canvas.current,rasterScale,pixels:canvas.current.width*canvas.current.height,near:true,used:++pageBitmapTick,onDrop:()=>{if(canvas.current?.isConnected){setRendered(false);setBitmapVersion(version=>version+1);}}};
          entry.current=value;pageBitmapCache.set(number,value);setRendered(true);trimPageBitmapCache();
        })().catch(error=>{if(!cancelled&&error.name!=='RenderingCancelledException'&&error.name!=='AbortException')onFailure(error.message);});
        return()=>{cancelled=true;renderTask?.cancel();textLayer?.cancel();};
      },[pdf,near,rasterScale,bitmapVersion]);
      return h('div',{ref,className:'pr-page','data-page':number,style:{width:baseViewport.width*scale,height:baseViewport.height*scale}},
        !rendered&&h('div',{key:'skeleton',className:'pr-page-skeleton',role:'status','aria-label':label}),h('canvas',{ref:canvas,style:{visibility:rendered?'visible':'hidden'}}),h('div',{ref:text,className:'pr-text-root',style:{width:baseViewport.width*textScale,height:baseViewport.height*textScale,transform:`scale(${scale/textScale})`}}),
        h('div',{className:'pr-highlight-layer'},...annotations.flatMap(a=>a.rects.filter(r=>r.page===number).map((r,i)=>h('div',{key:a.id+'-'+i,className:'pr-hl',style:{left:r.x*100+'%',top:r.y*100+'%',width:r.width*100+'%',height:r.height*100+'%'}})))),
        h('div',{className:'pr-link-layer'},...links.map((link,i)=>h('a',{key:link.id||i,className:'pr-pdf-link',href:link.url||'#',...(link.url?{target:'_blank',rel:'noopener noreferrer'}:{onClick:event=>{event.preventDefault();onLink(link.dest);}}),title:link.url||'PDF link','aria-label':link.url||'PDF link',style:{left:link.left*100+'%',top:link.top*100+'%',width:link.width*100+'%',height:link.height*100+'%'}}))),
        ...find.map((r,i)=>h('div',{key:'find-'+i,className:'pr-find','data-active':r.active,style:{left:r.x*100+'%',top:r.y*100+'%',width:r.width*100+'%',height:r.height*100+'%'}})));
    }
    const readingPositions=new Map(), READING_POSITION_PREFIX='pdf-reading-position:';
    function readReadingPosition(id){
      if(readingPositions.has(id))return readingPositions.get(id);
      try{
        const value=JSON.parse(window.localStorage.getItem(READING_POSITION_PREFIX+id));
        if(!value||!Number.isInteger(value.page)||value.page<1||!Number.isFinite(value.offset)||value.offset < -1||value.offset>1||!Number.isFinite(value.horizontal)||value.horizontal < -1||value.horizontal>1||!Number.isFinite(value.scale)||value.scale<.2||value.scale>5)return null;
        readingPositions.set(id,value);return value;
      }catch(error){return null;}
    }
    function captureReadingPosition(element,pageElements,scale){
      const list=Array.from(pageElements||[]);if(!element||!list.length||!Number.isFinite(scale))return null;
      const page=list.find(item=>item.offsetTop+item.offsetHeight>element.scrollTop)||list[list.length-1];
      if(!page.offsetHeight||!page.offsetWidth)return null;
      return {page:Number(page.dataset.page),offset:Math.max(-1,Math.min(1,(element.scrollTop-page.offsetTop)/page.offsetHeight)),horizontal:Math.max(-1,Math.min(1,(element.scrollLeft-page.offsetLeft)/page.offsetWidth)),scale};
    }
    function persistReadingPosition(id,value){
      if(!id||!value)return;
      readingPositions.set(id,value);
      try{window.localStorage.setItem(READING_POSITION_PREFIX+id,JSON.stringify(value));}catch(error){/* View preferences are optional. */}
    }
    const CHAT_ZOOM_KEY='pdf-reading-chat-zoom',CHAT_ZOOM_MIN=.8,CHAT_ZOOM_MAX=2.4;
    function storedChatZoom() {
      try {
        const value=Number(window.localStorage.getItem(CHAT_ZOOM_KEY));
        return Number.isFinite(value)&&value>=CHAT_ZOOM_MIN&&value<=CHAT_ZOOM_MAX?value:1;
      } catch (error) { return 1; }
    }
    function Reader(props) {
      const {t,model}=props,state=props.useReading(s=>s);const paper=state.papers.find(p=>p.id===state.selected);const [documentState,setDocument]=useState(null),[scale,setScale]=useState(1),[rasterScale,setRasterScale]=useState(1),[viewportWidth,setViewportWidth]=useState(800),[chatWidth,setChatWidth]=useState(36),[pageDraft,setPageDraft]=useState('1'),[chatZoom,setChatZoom]=useState(storedChatZoom),[findOpen,setFindOpen]=useState(false),[findQuery,setFindQuery]=useState(''),[findMatches,setFindMatches]=useState([]),[findIndex,setFindIndex]=useState(0),[findBusy,setFindBusy]=useState(false);const scroll=useRef(null),pages=useRef(null),workspace=useRef(null),picker=useRef(null),engine=useRef(null),zoom=useRef({scale:1,target:1,preview:1,timer:null,frame:null,anchor:null}),selectionRef=useRef(null),chatBody=useRef(null),chatZoomRef=useRef(chatZoom),chatZoomSave=useRef(null),findInput=useRef(null),findCache=useRef(new Map());
      const positionRef=useRef(null),positionTimer=useRef(null),restoredDocument=useRef(null);
      const sessionRows=props.useSessions(s=>s.byId);
      const chatResource=props.useResource(state.chatSessionId?'dsh-resource://pdfreadingchat/'+state.chatSessionId:'');
      useEffect(()=>{const observer=new ResizeObserver(()=>setViewportWidth(scroll.current.clientWidth));observer.observe(scroll.current);return()=>observer.disconnect();},[]);
      function showError(message){model.patch({error:message});}
      useEffect(()=>{if(window.__PDFLIGHT_EMBED__)return;let cancelled=false,task,opened;setDocument(null);selectionRef.current=null;findCache.current.clear();setFindMatches([]);setFindIndex(0);setFindOpen(false);setFindQuery('');model.patch({outline:[],pages:0,page:1,jump:null});if(!paper)return;
        (async()=>{const pdfjs=await import('/pdf-reading/assets/pdf.mjs');pdfjs.GlobalWorkerOptions.workerSrc='/pdf-reading/assets/pdf.worker.mjs';engine.current=pdfjs;task=pdfjs.getDocument({url:'/pdf-reading/file?id='+encodeURIComponent(paper.id),cMapUrl:'/pdf-reading/assets/cmaps/',cMapPacked:true,standardFontDataUrl:'/pdf-reading/assets/standard_fonts/',disableFontFace:true});opened=await task.promise;if(cancelled){await opened.destroy();return;}const first=await opened.getPage(1);const viewport=first.getViewport({scale:1});const dimensions=[];for(let n=1;n<=opened.numPages;n++){const page=n===1?first:await opened.getPage(n);dimensions.push(page.getViewport({scale:1}));if(cancelled)return;}const position=readReadingPosition(paper.id);const nextScale=position?.scale??Math.min(2,Math.max(.25,(scroll.current.clientWidth-48)/viewport.width));zoom.current.scale=nextScale;zoom.current.target=nextScale;zoom.current.preview=nextScale;setScale(nextScale);setRasterScale(nextScale);setDocument({pdf:opened,pdfjs,dimensions,paperId:paper.id,position});model.patch({pages:opened.numPages});const tree=await opened.getOutline();const outline=[];async function flatten(nodes,depth=0){for(const item of nodes||[]){try{const destination=typeof item.dest==='string'?await opened.getDestination(item.dest):item.dest;if(destination){const page=typeof destination[0]==='number'?destination[0]+1:await opened.getPageIndex(destination[0])+1;outline.push({title:item.title,page,depth});}}catch(error){/* A malformed bookmark does not prevent reading. */}await flatten(item.items,depth+1);}}await flatten(tree);if(!cancelled)model.patch({outline});})().catch(error=>{if(!cancelled)showError(error.message);});
        return()=>{cancelled=true;clearTimeout(zoom.current.timer);if(zoom.current.frame!==null)cancelAnimationFrame(zoom.current.frame);zoom.current.frame=null;flushPosition();task?.destroy();};
      },[paper?.id]);
      function flushPosition(){
        clearTimeout(positionTimer.current);positionTimer.current=null;
        if(positionRef.current)persistReadingPosition(positionRef.current.id,positionRef.current.value);
      }
      function rememberPosition(){
        if(!paper||!documentState||documentState.paperId!==paper.id||restoredDocument.current!==documentState.pdf)return;
        const value=captureReadingPosition(scroll.current,pages.current?.children,zoom.current.scale);if(!value)return;
        if(positionRef.current&&positionRef.current.id!==paper.id)flushPosition();
        positionRef.current={id:paper.id,value};readingPositions.set(paper.id,value);
        clearTimeout(positionTimer.current);positionTimer.current=setTimeout(flushPosition,180);
      }
      useLayoutEffect(()=>{
        if(!documentState||!scroll.current||documentState.paperId!==paper?.id)return;
        const element=scroll.current;
        if(restoredDocument.current!==documentState.pdf){
          restoredDocument.current=documentState.pdf;
          const position=documentState.position,page=position&&pages.current?.children[Math.min(position.page,documentState.dimensions.length)-1];
          if(page){
            element.scrollTop=page.offsetTop+position.offset*page.offsetHeight;
            element.scrollLeft=page.offsetLeft+position.horizontal*page.offsetWidth;
          }else{element.scrollTop=0;element.scrollLeft=(element.scrollWidth-element.clientWidth)/2;}
          const visible=Array.from(pages.current?.children||[]).find(item=>item.offsetTop+item.offsetHeight>element.scrollTop+element.clientHeight*.3);
          const number=Number(visible?.dataset.page)||1;model.patch({page:number});setPageDraft(String(number));rememberPosition();
        }
      },[documentState,viewportWidth,scale,paper?.id]);
      function captureAnchor(x,y){
        const area=scroll.current.getBoundingClientRect();let best=null;
        for(const element of pages.current?.children||[]){const rect=element.getBoundingClientRect();if(rect.bottom>=y){best={element,rx:(x-rect.left)/rect.width,ry:(y-rect.top)/rect.height,x:x-area.left,y:y-area.top};break;}}
        return best;
      }
      function applyPendingZoom(){
        const current=zoom.current;current.frame=null;
        if(!documentState||!scroll.current||Math.abs(current.target-current.scale)<.000001)return;
        const area=scroll.current.getBoundingClientRect(),x=area.left+area.width/2,y=area.top+area.height/2;
        const anchor=captureAnchor(x,y),nextScale=current.target;
        current.scale=nextScale;current.preview=nextScale;
        flushSync(()=>setScale(nextScale));
        scroll.current.scrollLeft=(scroll.current.scrollWidth-scroll.current.clientWidth)/2;
        if(anchor){const rect=anchor.element.getBoundingClientRect();scroll.current.scrollTop+=rect.top-area.top+anchor.ry*rect.height-anchor.y;}
        rememberPosition();
      }
      function finishZoom(){
        const current=zoom.current;clearTimeout(current.timer);current.timer=null;
        if(current.frame!==null){cancelAnimationFrame(current.frame);current.frame=null;applyPendingZoom();}
        setRasterScale(current.scale);
      }
      function requestZoom(next,x,y,immediate=false){
        if(!documentState||!scroll.current)return;
        const current=zoom.current,nextScale=Math.max(.2,Math.min(5,next));
        if(Math.abs(nextScale-current.target)<.000001)return;
        current.target=nextScale;clearTimeout(current.timer);
        if(immediate){if(current.frame!==null)cancelAnimationFrame(current.frame);current.frame=null;applyPendingZoom();setRasterScale(current.scale);}
        else{if(current.frame===null)current.frame=requestAnimationFrame(applyPendingZoom);current.timer=setTimeout(finishZoom,160);}
      }
      useEffect(()=>{
        const element=scroll.current;
        const wheel=event=>{if(!(event.ctrlKey||event.metaKey)||!documentState)return;event.preventDefault();requestZoom(zoom.current.target*Math.exp(-event.deltaY*.004),event.clientX,event.clientY);};
        let startScale=1;
        const begin=event=>{event.preventDefault();startScale=zoom.current.target;};
        const change=event=>{event.preventDefault();requestZoom(startScale*event.scale,event.clientX,event.clientY);};
        const end=event=>{event.preventDefault();finishZoom();};
        element.addEventListener('wheel',wheel,{passive:false});element.addEventListener('gesturestart',begin,{passive:false});element.addEventListener('gesturechange',change,{passive:false});element.addEventListener('gestureend',end,{passive:false});
        return()=>{element.removeEventListener('wheel',wheel);element.removeEventListener('gesturestart',begin);element.removeEventListener('gesturechange',change);element.removeEventListener('gestureend',end);};
      },[documentState]);
      useEffect(()=>{const element=chatBody.current;if(!element)return;element.style.zoom=String(chatZoom);clearTimeout(chatZoomSave.current);chatZoomSave.current=setTimeout(()=>{try{window.localStorage.setItem(CHAT_ZOOM_KEY,String(chatZoom));}catch(error){/* A blocked storage keeps the live value. */}},260);},[chatZoom]);
      useEffect(()=>()=>{clearTimeout(chatZoomSave.current);try{window.localStorage.setItem(CHAT_ZOOM_KEY,String(chatZoomRef.current));}catch(error){/* A blocked storage keeps the live value. */}},[]);
      useEffect(()=>{
        const element=chatBody.current;if(!element)return;
        const apply=next=>{const value=Math.min(CHAT_ZOOM_MAX,Math.max(CHAT_ZOOM_MIN,next));if(Math.abs(value-chatZoomRef.current)<.001)return;chatZoomRef.current=value;flushSync(()=>setChatZoom(value));};
        const wheel=event=>{if(!(event.ctrlKey||event.metaKey))return;event.preventDefault();apply(chatZoomRef.current*Math.exp(-event.deltaY*.004));};
        let start=1;
        const begin=event=>{event.preventDefault();start=chatZoomRef.current;};
        const change=event=>{event.preventDefault();apply(start*event.scale);};
        const end=event=>{event.preventDefault();};
        element.addEventListener('wheel',wheel,{passive:false});element.addEventListener('gesturestart',begin,{passive:false});element.addEventListener('gesturechange',change,{passive:false});element.addEventListener('gestureend',end,{passive:false});
        return()=>{element.removeEventListener('wheel',wheel);element.removeEventListener('gesturestart',begin);element.removeEventListener('gesturechange',change);element.removeEventListener('gestureend',end);};
      },[]);
      useEffect(()=>{
        if(!findOpen||!documentState)return;
        const term=findQuery.trim().toLocaleLowerCase();
        if(!term){setFindMatches([]);setFindIndex(0);setFindBusy(false);return;}
        let cancelled=false;setFindBusy(true);
        const timer=setTimeout(async()=>{
          try{
            const found=[];
            for(let number=1;number<=documentState.pdf.numPages&&!cancelled&&found.length<500;number++){
              let index=findCache.current.get(number);
              if(!index){
                const page=await documentState.pdf.getPage(number);
                const content=await page.getTextContent();
                if(cancelled)return;
                index=buildPageIndex(documentState.pdfjs,page.getViewport({scale:1}),content);
                findCache.current.set(number,index);
              }
              const haystack=index.text.toLocaleLowerCase();
              let at=haystack.indexOf(term);
              while(at>=0&&found.length<500){
                found.push({page:number,rects:matchRects(index,at,at+term.length)});
                at=haystack.indexOf(term,at+Math.max(1,term.length));
              }
            }
            if(cancelled)return;
            setFindMatches(found);setFindIndex(0);setFindBusy(false);
            if(found.length)jumpToMatch(found[0]);
          }catch(error){if(!cancelled){setFindBusy(false);showError(error.message);}}
        },220);
        return()=>{cancelled=true;clearTimeout(timer);};
      },[findQuery,findOpen,documentState]);
      useEffect(()=>{const key=event=>{if(!primaryModifier(event)||event.altKey||event.shiftKey||event.key.toLowerCase()!=='f'||!documentState||state.searchOpen)return;event.preventDefault();setFindOpen(true);requestAnimationFrame(()=>{findInput.current?.focus();findInput.current?.select();});};window.addEventListener('keydown',key,true);return()=>window.removeEventListener('keydown',key,true);},[documentState,state.searchOpen]);
      function jumpToMatch(match){
        if(!match||!scroll.current)return;
        const page=pages.current?.querySelector('[data-page="'+match.page+'"]');
        if(!page)return;
        const areaRect=scroll.current.getBoundingClientRect(),pageRect=page.getBoundingClientRect();
        scroll.current.scrollTop=Math.max(0,pageRect.top-areaRect.top+scroll.current.scrollTop+(match.rects[0]?.y||0)*pageRect.height-36);
        if(state.page!==match.page){model.patch({page:match.page});setPageDraft(String(match.page));}
      }
      function stepFind(delta){
        if(!findMatches.length)return;
        const next=(findIndex+delta+findMatches.length)%findMatches.length;
        setFindIndex(next);jumpToMatch(findMatches[next]);
      }
      function closeFind(){setFindOpen(false);setFindQuery('');setFindMatches([]);setFindIndex(0);}
      useEffect(()=>{if(!state.jump||!documentState)return;const el=pages.current?.querySelector('[data-page="'+state.jump.page+'"]');if(el){scroll.current.scrollTop=el.offsetTop+(state.jump.offset||0)*el.offsetHeight-16;model.patch({page:state.jump.page});setPageDraft(String(state.jump.page));}},[state.jump,documentState]);
      function collectSelection(){selectionRef.current=null;const selected=window.getSelection();if(!selected||selected.isCollapsed||!selected.rangeCount||!pages.current?.contains(selected.anchorNode)||!pages.current?.contains(selected.focusNode)){selectionRef.current=null;return;}const range=selected.getRangeAt(0),rects=[];for(const page of pages.current.children){if(!range.intersectsNode(page))continue;const bounds=page.getBoundingClientRect();const spans=page.querySelectorAll('.textLayer span');for(const span of spans){if(!range.intersectsNode(span)||!span.firstChild||span.firstChild.nodeType!==3)continue;const sub=document.createRange();sub.selectNodeContents(span);if(range.startContainer===span.firstChild)sub.setStart(span.firstChild,range.startOffset);if(range.endContainer===span.firstChild)sub.setEnd(span.firstChild,range.endOffset);for(const r of sub.getClientRects()){if(r.width<.5||r.height<.5)continue;const x=Math.max(0,r.left-bounds.left),y=Math.max(0,r.top-bounds.top);rects.push({page:Number(page.dataset.page),x:x/bounds.width,y:y/bounds.height,width:Math.min(r.width,bounds.width-x)/bounds.width,height:Math.min(r.height,bounds.height-y)/bounds.height});}}}if(!rects.length)return;selectionRef.current={text:selected.toString(),rects,page:rects[0].page};}
      function addHighlight(){const value=selectionRef.current;if(!value)return;const erased=eraseHighlightSelection(state.annotations,value.rects);const annotations=erased.changed?erased.annotations:[...state.annotations,{id:crypto.randomUUID(),text:value.text,page:value.page,rects:value.rects,createdAt:new Date().toISOString()}];model.save(annotations).then(()=>{window.getSelection()?.removeAllRanges();selectionRef.current=null;}).catch(()=>{});}
      useEffect(()=>{const key=e=>{if(!primaryModifier(e)||e.altKey||e.key.toLowerCase()!=='e'||editableTarget(e.target))return;collectSelection();const selected=window.getSelection();if(!selectionRef.current||!selected||selected.isCollapsed||!pages.current?.contains(selected.anchorNode)||!pages.current?.contains(selected.focusNode))return;e.preventDefault();e.stopPropagation();if(e.shiftKey)quote();else addHighlight();};window.addEventListener('keydown',key,true);return()=>window.removeEventListener('keydown',key,true);},[state.annotations,state.selected,state.chatSessionId,state.chatBusy,paper?.id]);
      useEffect(()=>{const key=event=>{if(!primaryModifier(event)||event.altKey||event.key.toLowerCase()!=='z'||editableTarget(event.target))return;if(event.shiftKey?!model.canRedo():!model.canUndo())return;event.preventDefault();event.stopPropagation();void (event.shiftKey?model.redo():model.undo());};window.addEventListener('keydown',key,true);return()=>window.removeEventListener('keydown',key,true);},[]);
      function quote(){const value=selectionRef.current;if(!value)return;if(!state.chatSessionId||state.chatBusy){showError(t('unavailable'));return;}const prefix=`[${paperLabel(paper.title)} · p. ${value.page}]\n${value.text}\n\n`;model.patch({pendingQuote:{sessionId:state.chatSessionId,text:prefix,nonce:Date.now()}});window.getSelection()?.removeAllRanges();selectionRef.current=null;}
      function jump(page){page=Math.max(1,Math.min(state.pages,Number(page)||1));model.patch({jump:{page,nonce:Date.now()}});}
      async function followPdfLink(destination){
        const pdf=documentState?.pdf,paperId=paper?.id;if(!pdf||!destination)return;
        try{
          const target=await resolvePdfDestination(pdf,destination);
          if(target&&model.source.getSnapshot().selected===paperId)model.patch({jump:{...target,nonce:Date.now()}});
        }catch(error){showError(error.message);}
      }
      const findByPage=new Map();
      findMatches.forEach((match,index)=>{const list=findByPage.get(match.page)||[];for(const rect of match.rects)list.push({...rect,active:index===findIndex});findByPage.set(match.page,list);});
      const chat=chatResource.value?h(props.SessionProvider,{session:chatResource.value.reference},props.renderSlot('pdf-reading.chat',{})):h('div',{className:'pr-chat-placeholder'},state.chatError||chatResource.failure?.message||t(paper?(state.chatBusy||state.chatSessionId?'chatLoading':'noChats'):'chatEmpty'),(state.chatError||chatResource.status==='failed')&&h('button',{onClick:()=>model.openChat()},t('chatRetry')));
      return h('div',{ref:workspace,className:'pr-workspace',style:{gridTemplateColumns:`minmax(280px,1fr) 5px minmax(310px,${chatWidth}%)`}},
        h('style',null,css+refinedCss),
        h('section',{className:'pr-reader',onDragOver:event=>{if(dragKind(event.dataTransfer)){stopDrop(event);event.dataTransfer.dropEffect=dragKind(event.dataTransfer)==='files'?'copy':'none';}},onDrop:event=>{const kind=dragKind(event.dataTransfer);if(kind){stopDrop(event);if(kind==='files')return model.importFiles(event.dataTransfer.files);}}},
        h('div',{className:'pr-toolbar','data-window-drag':true},
        h('span',{className:'pr-name',title:paper?.title},paperLabel(paper?.title)||t('mode')),paper&&h('select',{'aria-label':t('move'),value:paper.category,onChange:e=>model.movePaper(paper.id,e.target.value)},...state.categories.map(c=>h('option',{value:c,key:c},c))),
        h('button',{title:t('previous'),disabled:!state.pages||state.page<=1,onClick:()=>jump(state.page-1)},'‹'),
        h('input',{'aria-label':t('page'),value:pageDraft,disabled:!state.pages,onChange:e=>setPageDraft(e.target.value),onKeyDown:e=>{if(e.key==='Enter')jump(pageDraft);},onBlur:()=>jump(pageDraft)}),
        h('span',null,'/ '+state.pages),
        h('button',{title:t('next'),disabled:!state.pages||state.page>=state.pages,onClick:()=>jump(state.page+1)},'›'),
        h('button',{title:t('zoomOut'),disabled:!documentState,onClick:()=>requestZoom(scale/1.15,undefined,undefined,true)},'−'),
        h('span',null,Math.round(scale*100)+'%'),
        h('button',{title:t('zoomIn'),disabled:!documentState,onClick:()=>requestZoom(scale*1.15,undefined,undefined,true)},'+'),
        h('button',{disabled:!documentState,onClick:()=>requestZoom((scroll.current.clientWidth-48)/documentState.dimensions[0].width,undefined,undefined,true)},t('fit'))),findOpen&&h('div',{className:'pr-find-bar',role:'search'},
        h('input',{ref:findInput,value:findQuery,placeholder:t('findPlaceholder'),'aria-label':t('findPlaceholder'),autoComplete:'off',spellCheck:false,onChange:event=>setFindQuery(event.target.value),onKeyDown:event=>{if(event.key==='Escape'){event.preventDefault();event.stopPropagation();closeFind();}else if(event.key==='Enter'){event.preventDefault();stepFind(event.shiftKey?-1:1);}}}),
        h('span',{className:'pr-find-count',role:'status'},findBusy?t('finding'):findQuery.trim()?(findMatches.length?(findIndex+1)+'/'+findMatches.length:t('noMatch')):''),
        h('button',{disabled:!findMatches.length,title:t('findPrevious'),'aria-label':t('findPrevious'),onClick:()=>stepFind(-1)},'↑'),
        h('button',{disabled:!findMatches.length,title:t('findNext'),'aria-label':t('findNext'),onClick:()=>stepFind(1)},'↓'),
        h('button',{title:t('cancel'),'aria-label':t('cancel'),onClick:closeFind},'×')),state.error&&h('div',{className:'pr-error',role:'alert'},state.error),
        h('div',{ref:scroll,className:'pr-scroll',onMouseUp:()=>setTimeout(collectSelection,0),onScroll:()=>{rememberPosition();const el=scroll.current;for(const page of pages.current?.children||[]){if(page.offsetTop+page.offsetHeight>el.scrollTop+el.clientHeight*.3){const number=Number(page.dataset.page);if(number!==state.page){model.patch({page:number});setPageDraft(String(number));}break;}}}},documentState?h('div',{className:'pr-pages',ref:pages},...documentState.dimensions.map((viewport,i)=>h(PdfPage,{key:paper.id+'-'+i,pdf:documentState.pdf,pdfjs:documentState.pdfjs,number:i+1,baseViewport:viewport,scale,rasterScale,annotations:state.annotations,root:scroll,onFailure:showError,onLink:followPdfLink,label:t('pageRendering'),find:findByPage.get(i+1)||[]}))):h('div',{className:'pr-empty'},
        h(Icon,{size:45}),
        h('h2',null,t(paper?'loading':'empty')),
        h('p',null,t('hint')),!paper&&h('button',{className:'pr-primary',onClick:()=>picker.current.click()},t('select')))),
        h('input',{hidden:true,type:'file',multiple:true,accept:'.pdf',ref:picker,onChange:e=>{model.importFiles(e.target.files);e.target.value='';}}),
        h('div',{className:'pr-status'},
        h('span',null,t('pinch')),
        h('span',{role:'status'},state.notice?t(state.notice):''))),
        h('div',{className:'pr-divider',role:'separator','aria-orientation':'vertical',onPointerDown:e=>{e.preventDefault();e.currentTarget.setPointerCapture(e.pointerId);},onPointerMove:e=>{if(e.buttons!==1)return;const rect=workspace.current.getBoundingClientRect();setChatWidth(Math.max(26,Math.min(55,(rect.right-e.clientX)/rect.width*100)));}}),
        h('section',{className:'pr-chat'},
        h('div',{className:'pr-chat-head','data-window-drag':true},
        h(ConversationTabs,{t,conversations:state.conversations,sessionRows,paperTitle:paperLabel(paper?.title),selected:state.chatSessionId,busy:state.chatBusy,onDelete:id=>model.openChat('delete',id),onSelect:id=>{if(id!==state.chatSessionId)model.openChat('select',id);}}),
        chatZoom!==1&&h('button',{className:'pr-zoom-chip',title:t('chatZoomReset'),'aria-label':t('chatZoomReset'),onClick:()=>{chatZoomRef.current=1;setChatZoom(1);}},Math.round(chatZoom*100)+'%'),
        h('button',{onClick:()=>model.openChat('create'),disabled:!paper||state.chatBusy,title:t('newChat')},'+ '+t('newChat'))),
        h('div',{className:'pr-chat-prompt'},
        h('label',{htmlFor:'pr-prompt-preset'},t('promptLabel')),
        h('select',{id:'pr-prompt-preset','aria-label':t('promptLabel'),value:state.promptPreset,disabled:!state.promptPresets.length||state.promptBusy,onChange:event=>model.patch({promptPreset:event.target.value})},state.promptPresets.length?state.promptPresets.map(preset=>h('option',{key:preset.id,value:preset.id,title:preset.description},t('preset_'+preset.id))):h('option',{value:'reading'},t('promptLoading'))),
        h('button',{disabled:!state.chatSessionId||state.chatBusy||state.promptBusy||!state.promptPresets.length,onClick:()=>model.fillPrompt(selectionRef.current?.text,state.page)},t('applyPrompt')),
        h('button',{className:'pr-record-action',disabled:!state.chatSessionId||state.chatBusy,onClick:()=>model.openChatFolder(),title:state.chatRecord?.archivePath?t('openChatFolder')+' · '+state.chatRecord.archivePath:t('openChatFolder'),'aria-label':t('openChatFolder')},'▤'),
        !state.chatBusy&&state.chatRecord?.sessionId===state.chatSessionId&&state.chatRecord.web?.url&&h('a',{className:'pr-record-action',href:state.chatRecord.web.url,target:'_blank',rel:'noopener noreferrer',title:t('openWebChat'),'aria-label':t('openWebChat')},'↗')),state.chatRecordError&&h('div',{className:'pr-error',role:'alert'},state.chatRecordError),state.chatRecovery&&h('div',{className:'pr-chat-placeholder',role:'status'},t('chatRecovered')),state.chatError&&h('div',{className:'pr-error',role:'alert'},state.chatError),state.promptError&&h('div',{className:'pr-error',role:'alert'},state.promptError),
        h('div',{ref:chatBody,className:'pr-native-chat',id:'pr-chat-panel',role:'tabpanel','data-chat-zoom':chatZoom,'aria-labelledby':state.chatSessionId?'pr-chat-tab-'+state.chatSessionId:undefined},chat)));
    }
    globalThis.__PDReading = {ConversationTabs, paperLabel, dictionaries};
    return {inject:['slots','locale','layout','sessions','resources'],apply(ctx) {
      ctx.effect(()=>ctx.locale.register(NS,'zh',dictionaries.zh));ctx.effect(()=>ctx.locale.register(NS,'en',dictionaries.en));
      const t=ctx.locale.bind(NS),model=createModel();let active=false,disposeReading=[];
      const shared=()=>({model,exit,hooks:{reading:model.source}});
      function leave(){if(!active)return;active=false;model.deactivate();for(const dispose of disposeReading.reverse())dispose();disposeReading=[];}
      function exit(){leave();ctx.layout.selectPanel(null);}
      function HiddenRightbar(){useEffect(()=>{ctx.layout.closeRightbar();},[]);return null;}
      function enter(){
        if(active)return;active=true;
        disposeReading=[ctx.slots.inject('rightbar',()=>ctx.slots.register({name:'rightbar',priority:-100},HiddenRightbar)),ctx.slots.inject('sidebar',()=>ctx.slots.register({name:'sidebar',priority:-100,locale:NS,inject:shared},Sidebar))];
        ctx.layout.closeRightbar();void model.load();
      }
      function ReadingPage(props){useEffect(()=>{enter();window.addEventListener('dragover',blockFileNavigation);window.addEventListener('drop',blockFileNavigation);return()=>{window.removeEventListener('dragover',blockFileNavigation);window.removeEventListener('drop',blockFileNavigation);leave();};},[]);return h(Reader,props);}
      ctx.effect(()=>ctx.provide('pdfReadingNavigation',{active:()=>active,openSearch:()=>{if(active)model.patch({searchOpen:true});}}));
      ctx.effect(()=>ctx.resources.register({protocol:'pdfreadingchat',async *open(address,{signal}){
        const sessionId=new URL(address).pathname.slice(1);if(signal.aborted)return;
        const reference=ctx.sessions.retain(sessionId,{source:'sidebarChat',signal});
        try{
          await reference.ready;if(signal.aborted)return;
          yield {ok:true,value:{reference}};
          await new Promise(resolve=>{if(signal.aborted)resolve();else signal.addEventListener('abort',resolve,{once:true});});
        }catch(error){if(!signal.aborted)yield {ok:false,error:{code:'paper-session-open-failed',message:error.message,details:{}}};}
        finally{reference.release();}
      }}));
      ctx.slots.inject('sidebar.panellist',()=>ctx.slots.register({name:'sidebar.panellist',id:'pdf-reading',order:30,label:()=>t('mode')},Icon));
      ctx.slots.inject('main',()=>ctx.slots.register({name:'main',key:'pdf-reading',locale:NS,inject:shared,children:{'pdf-reading.chat':{kind:'single',scope:'session'}}},ReadingPage));
      ctx.slots.inject('pdf-reading.chat',()=>ctx.slots.register({name:'pdf-reading.chat',locale:NS,inject:shared},PaperChat));
      ctx.slots.inject('shell.overlay',()=>ctx.slots.register({name:'shell.overlay',id:'pdf-reading-search',order:70,locale:NS,inject:shared},PaperSearch));
      ctx.effect(()=>()=>leave());
    }};
  }
});
