/* Matteparken: novemberträd. Originalsprites bevaras och används igen efter november. */
(() => {
  "use strict";
  if (new Date().getMonth() !== 10) return;
  const source = {
    oak: "asset_062_e6fa1c4be76188c4.png",
    birch: "asset_058_c2b3c97f7ea84d02.png",
    pine: "asset_054_4dfcae2dcb3e2310.png",
    spruce: "asset_051_fb1c521950ecd068.png"
  };
  const autumn = Object.fromEntries(Object.entries(source).map(([kind,name]) => [kind, "assets/" + name]));
  const prepared = {};
  const leafColors = {oak:["#97602f","#b87939","#ca8b48","#d3a05e"],birch:["#ad8145","#c39852","#d4aa66","#e0b871"]};
  const pseudo = (x,y,seed=1) => {
    let n = (Math.imul(x+seed,374761393) + Math.imul(y+seed,668265263)) | 0;
    n = Math.imul(n ^ (n >>> 13),1274126177);
    return ((n ^ (n >>> 16)) >>> 0) / 4294967296;
  };
  function makeNovemberSprite(kind, image){
    const w=image.naturalWidth,h=image.naturalHeight;
    const canvas=document.createElement("canvas");canvas.width=w;canvas.height=h;
    const ctx=canvas.getContext("2d",{willReadFrequently:true});
    ctx.drawImage(image,0,0);
    const pixels=ctx.getImageData(0,0,w,h),d=pixels.data;
    const deciduous=kind==="oak"||kind==="birch";
    // Mjuka novembertoner och glesare löv i naturliga grupper.
    for(let y=0;y<h;y++){
      for(let x=0;x<w;x++){
        const p=(y*w+x)*4,a=d[p+3];
        if(a<10)continue;
        const r=d[p],g=d[p+1],b=d[p+2],max=Math.max(r,g,b),min=Math.min(r,g,b);
        const warm=r>g*1.10 && g>b*1.12 && r>90;
        const green=g>r*.74 && g>b*1.25 && max-min>18;
        const canopy=y<h*.77 && (x<w*.40 || x>w*.60 || y<h*.46);
        if(deciduous && warm && canopy){
          // Ta bort mindre lövklasar, inte stammen eller de synliga grenarna.
          const cluster=pseudo(Math.floor(x/29),Math.floor(y/28),kind==="oak"?8:13);
          if(cluster<.31 && pseudo(Math.floor(x/9),Math.floor(y/9),17)<.78){
            d[p+3]=0;continue;
          }
          d[p]=Math.min(255,Math.round(r*.89));
          d[p+1]=Math.round(g*.86);
          d[p+2]=Math.round(b*.88);
        } else if(!deciduous && green){
          d[p]=Math.round(r*.85);
          d[p+1]=Math.round(g*.89);
          d[p+2]=Math.round(b*.91);
        }
      }
    }
    ctx.putImageData(pixels,0,0);
    const leaf=(x,y,color,scale) => {
      ctx.fillStyle=color;
      ctx.fillRect(x,y,Math.max(2,3*scale),Math.max(2,2*scale));
      ctx.fillRect(x+2*scale,y-2*scale,Math.max(2,5*scale),Math.max(2,3*scale));
      ctx.fillRect(x+5*scale,y,Math.max(2,4*scale),Math.max(2,2*scale));
    };
    const cone=(x,y,scale) => {
      ctx.fillStyle="#4d3325";ctx.fillRect(x,y,8*scale,12*scale);
      ctx.fillStyle="#97633b";
      for(let i=0;i<3;i++)for(let j=0;j<2;j++)
        ctx.fillRect(x+(1+j*4)*scale,y+(2+i*3)*scale,3*scale,2*scale);
      ctx.fillStyle="#c2945b";ctx.fillRect(x+3*scale,y+2*scale,2*scale,2*scale);
    };
    // Markdetaljerna hör till själva spritesen och har äkta transparens.
    if(deciduous){
      const colors=leafColors[kind];
      for(let i=0;i<23;i++){
        const x=Math.round(w*(.22+.56*pseudo(i,4,3)));
        const y=Math.round(h*(.932+.042*pseudo(i,8,5)));
        leaf(x,y,colors[Math.floor(pseudo(i,2,7)*colors.length)],Math.max(1,Math.round(w/390)));
      }
    }else{
      for(let i=0;i<5;i++){
        const x=Math.round(w*(.32+.36*pseudo(i,3,9)));
        const y=Math.round(h*(.925+.037*pseudo(i,7,11)));
        cone(x,y,Math.max(1,Math.round(w/590)));
      }
    }
    return canvas.toDataURL("image/png");
  }
  const originals=Object.fromEntries(Object.entries(autumn).map(([kind,path])=>[path,kind]));
  // Endast novemberbilden ersätts i visningen. Sparade träd och årstidsvarianter är orörda.
  function swap(root=document){
    const images=[];
    if(root.nodeType===1 && root.matches?.("img"))images.push(root);
    root.querySelectorAll?.("img").forEach(img=>images.push(img));
    for(const img of images){
      const attr=img.getAttribute("src")||"";
      if(attr.startsWith("data:"))continue;
      const kind=Object.keys(source).find(key=>attr.includes(source[key]));
      if(!kind||!prepared[kind])continue;
      img.src=prepared[kind];
      img.dataset.novemberTree=kind;
    }
  }
  let pending=false;
  function update(){
    if(pending)return;
    pending=true;
    requestAnimationFrame(()=>{pending=false;swap();});
  }
  const observer=new MutationObserver(update);
  function start(){
    observer.observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:["src"]});
    // Use real transparent November PNG assets as soon as they exist in GitHub.
    // Until uploaded, fall back to the temporary generated late-autumn trees.
    const novemberFiles = {
      oak: "assets/november/ek.png",
      spruce: "assets/november/gran.png",
      pine: "assets/november/tall.png",
      birch: "assets/november/bjork.png"
    };
    for(const [kind,path] of Object.entries(autumn)){
      const fallback = () => {
        const image=new Image();
        image.onload=()=>{try{prepared[kind]=makeNovemberSprite(kind,image);update();}catch(err){console.warn("Novemberträd:",err);}};
        image.src=path;
      };
      const novemberImage=new Image();
      novemberImage.onload=()=>{prepared[kind]=novemberFiles[kind];update();};
      novemberImage.onerror=fallback;
      novemberImage.src=novemberFiles[kind];
    }
  }
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",start,{once:true});
  else start();
})();