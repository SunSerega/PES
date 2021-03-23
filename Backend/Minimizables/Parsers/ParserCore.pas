unit ParserCore;

interface

uses PathUtils        in '..\..\..\Utils\PathUtils';

uses MinimizableCore  in '..\..\MinimizableCore';

type
  ParsedFileItem = abstract class(MinimizableNode)
    
    public procedure UnWrapTo(sw: System.IO.StreamWriter; need_node: MinimizableNode->boolean); abstract;
    public function CountLines(need_node: MinimizableNode->boolean): integer; abstract;
    
  end;
  
  ParsedFile = abstract class(MinimizableContainer)
    protected rel_fname: string;
    
    public constructor(fname, base_dir, target: string);
    begin
      self.rel_fname := GetRelativePath(fname, base_dir);
      self.invulnerable := rel_fname=target;
    end;
    ///--
    public constructor := raise new System.InvalidOperationException;
    
    public static ParseByExt := new Dictionary<string, function(fname, base_dir, target:string):ParsedFile>;
    
  end;
  
implementation

uses ParserPas;

end.