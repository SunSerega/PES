unit MSPFileParser;

uses System.Windows;
uses System.Windows.Controls;
uses System.Windows.Media;

uses VUtils           in '..\VUtils';

uses MinimizableCore  in '..\..\Backend\MinimizableCore';
uses MFileParser      in '..\..\Backend\Minimizables\MFileParser';

uses MSPStandard;

type
  
  FileParserMSP = sealed class(StandardMSP)
    
    protected function MakeMinimizable(dir, target: string): MinimizableContainer; override :=
    new MFileBatch(dir, target);
    
    protected property Description: string read 'Parsed item removal'; override;
    
    public function MakeTestUIElement(_m: MinimizableContainer; need_node: MinimizableNode->boolean): System.Windows.UIElement;// override;
    begin
      var m := MFileBatch(_m);
      
      m.ForEachParsed(f->
      begin
        var sw := new System.IO.StringWriter;
        f.UnWrapTo(sw, nil); //ToDo
        var text := sw.ToString;
        
        var (deleted, added) := f.GetChangedSections(need_node);
        
        
      end);
      
    end;
    
  end;
  
end.