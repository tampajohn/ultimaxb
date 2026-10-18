import AppKit

/// Build a local art-direction preview. Generated imagery is not installed into the client.
@main struct Comparison {
    static func main() throws {
        let directory = URL(fileURLWithPath:"build/visual-upgrade")
        func bounds(_ name:String) throws -> [[Int]] {
            let image = NSImage(contentsOf:directory.appendingPathComponent(name))!
            var rect = NSRect(origin:.zero,size:image.size)
            let cg = image.cgImage(forProposedRect:&rect,context:nil,hints:nil)!
            let bitmap = NSBitmapImageRep(cgImage:cg)
            let width = bitmap.pixelsWide, height = bitmap.pixelsHigh
            return (0..<4).map { cell in
                let x0 = cell%2*width/2, y0 = cell/2*height/2
                var left = width,top = height,right = 0,bottom = 0
                for y in y0..<(y0+height/2) { for x in x0..<(x0+width/2) {
                    if (bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0)>0.5 {
                        left = min(left,x);top = min(top,y);right = max(right,x);bottom = max(bottom,y)
                    }
                } }
                return [left,top,right-left+1,bottom-top+1]
            }
        }
        let original = try bounds("character-original-reference.png")
        let modern = try bounds("character-modern-v1.png")
        let boxes = String(data:try JSONSerialization.data(withJSONObject:[original,modern]),encoding:.utf8)!
        let html = """
        <!doctype html><meta charset="utf-8"><title>UltimaXB character visual experiment</title>
        <style>
        body{background:#151b20;color:#e7e4da;font:16px system-ui;margin:24px}h1{font-size:24px}
        button,select{font:inherit;padding:8px;margin-right:8px;background:#29333c;color:inherit;border:1px solid #586875;border-radius:6px}
        .row{display:flex;flex-wrap:wrap;gap:24px}canvas{background:#27313a;max-width:100%;height:auto}
        p{max-width:900px;color:#bdc5ca;line-height:1.5}.panel{min-width:260px}label{display:inline-block;margin:8px 12px 16px 0}
        </style><h1>Character visual experiment</h1>
        <p>Original MUL frames versus a generated modernized concept. Both are normalized to the same character height.
        This is a visual preview; equipment is baked into the concept, and animation alignment is not yet validated.</p>
        <label>Facing <select id="direction"><option>Front</option><option>Side</option><option>Back</option><option>Opposite side</option></select></label>
        <label>Size <select id="zoom"><option value="1">Gameplay size</option><option value="2">2×</option><option value="4" selected>4× inspection</option></select></label>
        <div class="row"><div class="panel"><h2>Original</h2><canvas id="before" width="384" height="512"></canvas></div>
        <div class="panel"><h2>Modernized concept</h2><canvas id="after" width="384" height="512"></canvas></div></div>
        <h2>World context</h2><button id="swap">Showing modernized — switch to original</button><p>The world stays at its original resolution. This preview tests readability and style fit.</p>
        <canvas id="world" width="960" height="720"></canvas>
        <script>
        const boxes=\(boxes),images=[new Image(),new Image()],scene=new Image();let modern=true;
        images[0].src='character-original-reference.png';images[1].src='character-modern-v1.png';scene.src='world-reference.png';
        function sprite(ctx,which,cell,x,y,height){const b=boxes[which][cell],w=b[2]*height/b[3];ctx.imageSmoothingEnabled=which===1;ctx.drawImage(images[which],...b,x-w/2,y-height,w,height)}
        function draw(){if(!images.every(i=>i.complete&&i.naturalWidth)||!scene.complete||!scene.naturalWidth)return;
        const d=direction.selectedIndex,z=Number(zoom.value),h=boxes[0][d][3]/4;
        ['before','after'].forEach((id,i)=>{const c=document.getElementById(id),ctx=c.getContext('2d');ctx.clearRect(0,0,c.width,c.height);sprite(ctx,i,d,192,420,h*z)});
        const ctx=world.getContext('2d');ctx.drawImage(scene,0,0,960,720);sprite(ctx,modern?1:0,d,480,322,h)}
        images.forEach(i=>i.onload=draw);scene.onload=draw;direction.onchange=zoom.onchange=draw;
        swap.onclick=()=>{modern=!modern;swap.textContent=modern?'Showing modernized — switch to original':'Showing original — switch to modernized';draw()};
        </script>
        """
        try html.write(to:directory.appendingPathComponent("compare.html"),atomically:true,encoding:.utf8)
        print("build/visual-upgrade/compare.html")
    }
}
