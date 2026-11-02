const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
for(let i=0;i<100 && (!window.PDFlightReplaceMessages || !window.__setChatZoom);i++) await delay(20);
if(!window.PDFlightReplaceMessages || !window.__setChatZoom) throw new Error('Renderer not ready');
const answer = '# Reading parity 阅读体验\n\nFirst paragraph 第一段：A shared source should preserve typography, readable margins and wrapping. '.repeat(1)
  + '\n\nSecond paragraph **重点** and `inline code` with $x^2+y^2=z^2$.\n\n## Method 方法\n\n'
  + '- First list item 列表内容\n- Second item\n  - Nested content 嵌套内容\n\n'
  + '| Model | TRR Teacher Reward Ratio | Safety 防御成功率 | Length | Evaluation |\n|---|---|---|---|---|\n'
  + '| GRPO | Llama Guard sequence level reward | 95.2% | 1024 | LongIdentifier'.repeat(1) + 'Token'.repeat(25) + ' |\n'
  + '| EOPSA | Token level teacher supervision | 98.1% | 256 | Benchmarks |\n\n'
  + '> Blockquote with a narrow table\n>\n> | Item | Description |\n> |---|---|\n> | Value | 引用中的内容 |\n\n'
  + '$$\\mathcal{S}=\\{128,256,1024\\}$$\n\n```python\nprint("reading parity")\n```\n\nLast paragraph 最后一段。';
window.PDFlightReplaceMessages([{id:'parity-answer',role:'assistant',content:answer,createdAt:'2026-11-02T00:00:00Z'}, {id:'parity-user',role:'user',content:'请解释表格与方法。Explain this table.',createdAt:'2026-11-02T00:01:00Z'}]);
await delay(350);
return true;
