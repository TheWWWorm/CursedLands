export function normalize(value) {
  return value.toLowerCase().replaceAll('ё','е').replaceAll('ä','a').replaceAll('ö','o').replaceAll('ü','u').replaceAll('ß','ss').normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[–-]/g,' ').replace(/\s+/g,' ');
}
export function distance(a,b) {
  if(Math.abs(a.length-b.length)>2) return 99;
  const d=Array.from({length:a.length+1},(_,i)=>Array.from({length:b.length+1},(_,j)=>i===0?j:j===0?i:0));
  for(let i=1;i<=a.length;i++) for(let j=1;j<=b.length;j++) {
    d[i][j]=Math.min(d[i-1][j]+1,d[i][j-1]+1,d[i-1][j-1]+Number(a[i-1]!==b[j-1]));
    if(i>1&&j>1&&a[i-1]===b[j-2]&&a[i-2]===b[j-1]) d[i][j]=Math.min(d[i][j],d[i-2][j-2]+1);
  }
  return d[a.length][b.length];
}
export function score(query,title,text='') {
  query=normalize(query).trim(); if(!query) return 0;
  title=normalize(title); text=normalize(title+' '+text);
  if(query===title) return 1000;
  let rank=title.startsWith(query)?800:title.includes(query)?600:100;
  const words=text.split(/[^a-zа-я0-9]+/).filter(Boolean);
  for(const word of query.split(/\s+/)) {
    if(text.includes(word)) continue;
    if(word.length<4) return -1;
    const closest=Math.min(99,...words.map(candidate=>distance(word,candidate)));
    if(closest>(word.length<8?1:2)) return -1;
    rank-=closest*30;
  }
  return rank;
}
