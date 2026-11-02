import './assets/pdflight-static.js';
import { useHarnessChatZoom } from './harness-chat-zoom.js';
import { installHarnessWebKitCompatibility, isHarnessWebKit } from './harness-webkit-compat.js';
const C = {};
window.__ModuleLoader__ = {load(def){C[def.id] = def.factory(name => {if(!(name in window.__PD_STATIC__)) throw new Error('Missing '+name);return window.__PD_STATIC__[name]})}};
for(const name of ['dsh-client-ui-chat','dsh-client-ui-model-selection','dsh-client-ui-conversation','claude-warm-theme-client']) await new Promise((resolve,reject)=>{const s=document.createElement('script');s.src=name+'.js';s.onload=resolve;s.onerror=reject;document.head.append(s)});
C['@local/claude-warm-theme'].apply({effect:callback=>callback(),theme:{overrideTokens(name,tokens){
 const query=matchMedia('(prefers-color-scheme: dark)');
 const apply=()=>{document.body.toggleAttribute('data-ds-dark-theme',query.matches);for(const [key,value] of Object.entries(tokens))document.body.style.setProperty(key,query.matches?value.dark:value.light);};
 apply();query.addEventListener('change',apply);
 return()=>{query.removeEventListener('change',apply);for(const key of Object.keys(tokens))document.body.style.removeProperty(key);};
}}});
installHarnessWebKitCompatibility();
const React=window.__PD_STATIC__.react, root=window.__PD_STATIC__['react-dom/client'].createRoot(document.getElementById('root'));
const chat=C['@deepseek-ai/dsh-client-ui-chat'], conv=C['@deepseek-ai/dsh-client-ui-conversation'];
let data=[];
let nodes=new Map(data.map((m,i)=>[m.id, {key:m.id,kind:m.role,location:{kind:'session'},anchorSeq:i,data:m.role==='assistant'?{blocks:[{kind:'text',text:m.content}],status:'done'}:{content:[{type:'text',text:m.content}],time:new Date(m.createdAt).getTime()}}]));
let order=[...nodes.keys()], chatData={order,nodes,navigation:{items:()=>[]}};
const session={blank:false,awaitingFirstTurn:false,running:false,openState:'open',openError:null,hasMore:false,loadingOlder:false,pendingSubmissions:[]};
const useSession=f=>f(session), useChat=f=>f(chatData), useConversation=f=>f({activeTargets:new Set(),views:{grouped:()=>undefined}}),useSessions=f=>f({byId:{local:{cwd:''}}}),usePresentation=f=>f({mode:'chat',collapseTiming:'immediate'}),useProjection=(key,f)=>f?f(undefined):undefined;
const t=(key, values)=>{let v=chat.PDLocale[key]??key;if(values) for(const [k,x] of Object.entries(values))v=v.replaceAll('{'+k+'}',String(x));return v;};
const useGroupAction=()=>React.useRef(null), useStore=f=>f({}), chatScroll={read:()=>null,save:()=>{}};
function renderUserTextNode(name,p,options){
 const fallback=options.fallback;
 if(!isHarnessWebKit||name!=='conversation.user.text.node'||p.node.id!=='text'||typeof fallback?.props?.text!=='string')return fallback;
 const text=fallback.props.text,pieces=[];let cursor=0;
 // Safari can place a preserved word-separating space on a line of its own
 // when the bubble is narrower than one glyph. Chromium hangs that space at
 // the line end. Only those single interior spaces use normal whitespace;
 // every original character, indentation, newline and repeated space stays
 // in the original UserTextRun renderer and in the selectable DOM text.
 for(const match of text.matchAll(/\S (?=\S)/gu)){
  const space=match.index+match[0].length-1;
  if(space>cursor)pieces.push(React.cloneElement(fallback,{key:`text-${cursor}`,text:text.slice(cursor,space)}));
  pieces.push(React.createElement('span',{key:`space-${space}`,style:{whiteSpace:'normal'}},React.cloneElement(fallback,{text:' '})));
  cursor=space+1;
 }
 if(cursor===0)return fallback;
 if(cursor<text.length)pieces.push(React.cloneElement(fallback,{key:`text-${cursor}`,text:text.slice(cursor)}));
 return React.createElement(React.Fragment,null,...pieces);
}
function renderFactorySlot(name,p) {
 if(name==='conversation.chat.user.content')return React.createElement(chat.PDUserContent,{...p,renderFactorySlot,renderSlot,t});
 if(name==='conversation.user.text')return React.createElement(conv.PDUserText,{...p,useUserTextRevision:f=>f(0),createUserTextEvaluator:()=>({text})=>[{id:'text',start:0,end:text.length,data:{}}],reportTransformFailure:()=>{},renderSlot:p.ellipsis?(name,p,options)=>options.fallback:renderUserTextNode});
 return null;
}
function renderSlot(name,p,options={}) {
 if(name==='conversation.session')return React.createElement('div',{'data-slot':name,style:{display:'contents'}},React.createElement(conv.PDViews,{view:'chat',useSession,useConversation,useConversationViews:f=>f([{id:'chat'}]),useStore:f=>f({view:'chat'}),useInspectCall:f=>f(undefined),actions:{setDraft:()=>{}},inputActions:{persistDraft:()=>{}},bindDraftPersistence:()=>()=>{},openView:()=>{},renderSlot}));
 if(name==='conversation.view')return React.createElement(chat.PDChatView,props);
 if(name==='conversation.chat.node'){
  if(p.node.kind==='user') return React.createElement(chat.PDUser,{...p,renderFactorySlot,loadImage:async()=>null,t});
  if(p.node.kind==='assistant') return React.createElement(chat.PDAssistant,{...p,useDisclosure:()=>[false,()=>{}],useGroupAction,useTurnData:()=>undefined,usePresentation,renderSlot,t,loadImage:async()=>null});
 }
 if(name==='conversation.chat.flow')return React.createElement(chat.PDChatFlow,{...p,useSession,useChat,useChatNode:key=>nodes.get(key),useChatNodeBottom:()=>false,useChatNodeProcess:()=>undefined,useChatGroup:()=>undefined,usePresentation,useStore,actions:{},renderSlot,renderFactorySlot,t,useGroupAction,useGroupHeaderAction:useGroupAction});
 return options.fallback??null;
}
const props={useSession,useChat,useConversation,useSessions,renderSlot,sessionId:'local',openFile:async()=>{},openExternalLink:()=>{},loadOlder:async()=>{},loadThrough:async()=>{},loadImage:async()=>null,inspectCall:()=>{},chatScroll,forkAt:()=>{},fileMentions:()=>undefined,usePresentation,useProjection,t};
function FixedChatView(){return renderSlot('conversation.session',{view:'chat'});}
const contentProps={sessionId:'local',variant:'embedded',phase:'active',hero:false,useSession,useSessions,useSessionStatus:f=>f(new Map()),useWorkspaces:f=>f({items:[],phase:'ready'}),useInput:f=>f({draft:''}),useComposerBlock:f=>f(undefined),renderSlot,renderSlotChain:(name,p,options)=>options.fallback,selectWorkspace:async()=>{},t,useFactorySlot:(name,fallback)=>name==='views'?FixedChatView:fallback};

function ChatBody({revision}) {
 const ref=React.useRef(null);
 const {chatZoom,applyRef}=useHarnessChatZoom(React,window.__PD_STATIC__['react-dom'].flushSync,ref);
 const ratio=window.devicePixelRatio||1;
 const hairline=1/chatZoom;
 const actualHairline=Math.max(1/ratio,Math.floor(hairline*ratio)/ratio);
 const quoteBorder=Math.max(1,Math.floor(2*chatZoom))/chatZoom;
 const actualQuoteBorder=Math.max(1/ratio,Math.floor(quoteBorder*ratio)/ratio);
 const compatibilityLengths={
  '--pdflight-chromium-hairline':`${hairline}px`,
  '--pdflight-chromium-blockquote-border':`${quoteBorder}px`,
  '--pdflight-chromium-head-border-extra':`${hairline/2-Math.floor(actualHairline*ratio/2)/ratio}px`,
  '--pdflight-chromium-cell-border-extra':`${hairline-actualHairline}px`,
  '--pdflight-chromium-quote-border-extra':`${quoteBorder-actualQuoteBorder}px`,
 };
 React.useEffect(()=>{
  window.__setChatZoom=next=>applyRef.current?.(next);
  window.webkit?.messageHandlers?.harnessReady?.postMessage({ready:true});
  return()=>{delete window.__setChatZoom};
 },[]);
 return React.createElement('div',{className:'pr-workspace',style:{display:'flex'}},React.createElement('section',{className:'pr-chat',style:{flex:1}},React.createElement('div',{ref,id:'chat-body',className:'pr-native-chat',style:compatibilityLengths},React.createElement(conv.PDContent,{...contentProps,key:revision}))));
}
let revision=0;
window.PDFlightReplaceMessages=items=>{
 const scroller=[...document.querySelectorAll('#chat-body *')].find(e=>e.scrollHeight>e.clientHeight+20 && getComputedStyle(e).overflowY!=='visible');
 const previous=scroller?{top:scroller.scrollTop,bottom:scroller.scrollHeight-scroller.scrollTop-scroller.clientHeight<20}:null;
 data=items.map(m=>m.role==='tool'?{...m,role:'assistant',content:'**工具 · '+(m.toolEvent?.name??'')+'**\n\n'+(m.toolEvent?.arguments??'')+'\n\n'+(m.toolEvent?.result??'')}:m);
 nodes=new Map(data.map((m,i)=>[m.id,{key:m.id,kind:m.role,location:{kind:'session'},anchorSeq:i,data:m.role==='assistant'?{blocks:[{kind:'text',text:m.content}],status:'done'}:{content:[{type:'text',text:m.content}],time:new Date(m.createdAt).getTime()}}]));
 order=[...nodes.keys()];chatData={order,nodes,navigation:{items:()=>[]}};
 root.render(React.createElement(ChatBody,{revision:++revision}));
 if(previous)requestAnimationFrame(()=>{const next=[...document.querySelectorAll('#chat-body *')].find(e=>e.scrollHeight>e.clientHeight+20 && getComputedStyle(e).overflowY!=='visible');if(next)next.scrollTop=previous.bottom?next.scrollHeight:previous.top});
};
window.PDFlightReplaceMessages([]);
function apply(next){window.__setChatZoom(next)}
