const TYPES={Items:'item',Spells:'spell',Creatures:'creature',Materials:'material',Runes:'rune',Maps:'map',Quests:'quest'};
export function art(row,size=40){
  const img=document.createElement('img');img.alt='';img.width=size;img.height=size;img.loading='lazy';
  const fallback='./icon-'+(TYPES[row.category]||row.kind||'book')+'.svg';
  img.src=row.src|| (row.image?'/wiki/images/'+row.image+'.webp':fallback);
  if(!row.image)img.className='fallback-art';
  img.addEventListener('error',()=>{img.src=fallback;img.className='fallback-art';},{once:true});
  return img;
}
