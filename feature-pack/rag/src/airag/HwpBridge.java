// HWP parsing uses the separately configured Apache-2.0 hwplib dependency.
// Original input is read from stdin; only structured extraction is emitted.
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import kr.dogfoot.hwplib.reader.HWPReader;
import kr.dogfoot.hwplib.object.HWPFile;
import kr.dogfoot.hwplib.object.bodytext.ParagraphListInterface;
import kr.dogfoot.hwplib.object.bodytext.paragraph.Paragraph;
import kr.dogfoot.hwplib.object.bodytext.control.Control;
import kr.dogfoot.hwplib.object.bodytext.control.ControlTable;
import kr.dogfoot.hwplib.object.bodytext.control.table.*;
import kr.dogfoot.hwplib.object.bindata.EmbeddedBinaryData;

class HwpBridge {
    static final List<Object> blocks = new ArrayList<>();
    static final Set<String> unsupported = new TreeSet<>();
    static int paragraphCount = 0;
    static Map<String,Object> obj(Object... pairs) {
        Map<String,Object> m = new LinkedHashMap<>();
        for (int i=0;i<pairs.length;i+=2) m.put((String)pairs[i],pairs[i+1]);
        return m;
    }
    static String text(ParagraphListInterface ps) throws Exception {
        StringBuilder b=new StringBuilder();
        for(Paragraph p:ps) {
            String t=p.getNormalString();
            if(t!=null && !t.isEmpty()) { if(b.length()>0)b.append('\n'); b.append(t); }
        }
        return b.toString();
    }
    static void paragraphs(ParagraphListInterface ps,String path,int depth) throws Exception {
        if(depth>32)throw new IOException("nesting limit");
        int pi=0;
        for(Paragraph p:ps) {
            if(++paragraphCount>100000)throw new IOException("paragraph limit");
            String current=path+"/paragraph["+(pi++)+"]";
            String t=p.getNormalString();
            if(t!=null && !t.isEmpty()) blocks.add(obj("kind","text","path",current,"text",t));
            if(p.getControlList()==null)continue;
            int ci=0;
            for(Control c:p.getControlList()) {
                String cp=current+"/control["+(ci++)+"]";
                if(c instanceof ControlTable) {
                    List<Object> cells=new ArrayList<>();
                    for(Row r:((ControlTable)c).getRowList())for(Cell cell:r.getCellList()) {
                        ListHeaderForCell h=cell.getListHeader();
                        cells.add(obj("row",h.getRowIndex(),"col",h.getColIndex(),"row_span",h.getRowSpan(),"col_span",h.getColSpan(),"text",text(cell.getParagraphList())));
                    }
                    blocks.add(obj("kind","table","path",cp,"cells",cells));
                } else {
                    boolean represented=false;
                    try {
                        Object child=c.getClass().getMethod("getParagraphList").invoke(c);
                        if(child instanceof ParagraphListInterface) { paragraphs((ParagraphListInterface)child,cp,depth+1); represented=true; }
                    } catch(NoSuchMethodException ignored) {}
                    if(!represented)try {
                        Object tb=c.getClass().getMethod("getTextBox").invoke(c);
                        if(tb!=null) {
                            Object child=tb.getClass().getMethod("getParagraphList").invoke(tb);
                            if(child instanceof ParagraphListInterface) { paragraphs((ParagraphListInterface)child,cp,depth+1); represented=true; }
                        }
                    } catch(NoSuchMethodException ignored) {}
                    if(!represented) unsupported.add(c.getClass().getSimpleName());
                }
            }
        }
    }
    static void json(Object o,StringBuilder b) {
        if(b.length()>128*1024*1024)throw new IllegalArgumentException("output limit");
        if(o==null){b.append("null");return;}
        if(o instanceof String){
            b.append('"');
            for(char c:((String)o).toCharArray()) {
                if(c=='"'||c=='\\') b.append('\\').append(c);
                else if(c<32)b.append(String.format("\\u%04x",(int)c));
                else b.append(c);
            }
            b.append('"');
        } else if(o instanceof Map){
            b.append('{');boolean first=true;
            for(Object e0:((Map<?,?>)o).entrySet()){
                Map.Entry<?,?> e=(Map.Entry<?,?>)e0;
                if(!first)b.append(',');first=false;json(e.getKey(),b);b.append(':');json(e.getValue(),b);
            }
            b.append('}');
        } else if(o instanceof Iterable){
            b.append('[');boolean first=true;
            for(Object e:(Iterable<?>)o){if(!first)b.append(',');first=false;json(e,b);}b.append(']');
        } else b.append(o.toString());
    }
    public static void main(String[] args) throws Exception {
        byte[] bytes=System.in.readNBytes(64*1024*1024+1);
        if(bytes.length>64*1024*1024)throw new IOException("input limit");
        HWPFile file=HWPReader.fromInputStream(new ByteArrayInputStream(bytes));
        if(file==null || file.getFileHeader().hasPassword() || file.getFileHeader().isDRMDocument() || file.getFileHeader().isDistribution())throw new IOException("protected HWP unsupported");
        int section=0;
        for(var s:file.getBodyText().getSectionList()) paragraphs(s,"section["+(section++)+"]",0);
        List<Object> resources=new ArrayList<>();
        long total=0;
        for(EmbeddedBinaryData r:file.getBinData().getEmbeddedBinaryDataList()) {
            byte[] data=r.getData();total+=data.length;
            if(total>64*1024*1024)throw new IOException("resource limit");
            resources.add(obj("member",r.getName(),"byte_length",data.length,"content_base64",Base64.getEncoder().encodeToString(data)));
        }
        StringBuilder result=new StringBuilder();
        json(obj("blocks",blocks,"resources",resources,"unsupported_controls",unsupported),result);
        System.out.write(result.toString().getBytes(StandardCharsets.UTF_8));
    }
}
