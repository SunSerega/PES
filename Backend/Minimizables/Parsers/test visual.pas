## uses
  ParserCore,
  MinimizableCore in '..\..\MinimizableCore',
  MSPFileParser   in '..\..\..\Visual\MSP\MSPFileParser';

{$reference PresentationFramework.dll}
{$reference PresentationCore.dll}
{$reference WindowsBase.dll}

try
  
//  var t := new TextSection(' aba abababc ');
//  
//  t.Trim(' ').IndexOf('d').Println;
  
//  var fname := 'ParserPas.pas';
//  var fname := 'C:\0Prog\PES\Bucket\OpenCL.pas';
//  var fname := 'C:\0Prog\PES\Bucket\OpenCLABC.pas';
  var fname := 'C:\0Prog\PES\Bucket\Internal\OpenCLABCBase.pas';
//  var fname := 'C:\0Prog\POCGL\Modules.Packed\OpenGL.pas';
//  var fname := 'C:\0Prog\PES\Bucket\MatrMlt.pas';
  
  fname := System.IO.Path.GetFullPath(fname);
  var f: ParsedFile := ParsedFile.ParseByExt['.pas'](fname, System.IO.Path.GetDirectoryName(fname), nil);
//  f.Warnings.PrintLines;
  f.AssertIntegrity;
  
  {$apptype windows}
  var w := new System.Windows.Window;
  
  var dp := new System.Windows.Controls.DockPanel;
  w.Content := dp;
  
  var cc := new System.Windows.Controls.ContentControl;
  dp.Children.Add(cc);
  
  var text := default(string);
  begin
    var sw := new System.IO.StringWriter;
    f.UnWrapTo(sw, nil);
    text := sw.ToString;
  end;
  
  var all_removables := f.GetAllVulnerableChildren;
  var rem_ind := -1;
  var UpdateContent := procedure->
  begin
    var rem := if rem_ind=-1 then nil else all_removables[rem_ind];
    
    var rem_hs := new HashSet<MinimizableNode>(|rem|);
    if rem is MinimizableToken(var token) then
      token.AddDependants(rem_hs);
    
    w.Title := if rem=nil then '' else $'{rem.GetType}({rem_hs.Count})';
    
    var (rem_lst, add_lst) := f.GetChangedSections(n->not rem_hs.Contains(n));
    cc.Content := new MSPFileParser.CodeChangesWindow(text, rem_lst, add_lst, ind->f.GetIndexAreas(ind));
    
//    rem_lst.PrintLines;
//    Writeln('-'*30);
//    add_lst.PrintLines;
//    Writeln('='*30);
    
  end;
  UpdateContent;
  
  var sb := new System.Windows.Controls.Slider;
  dp.Children.Insert(0, sb);
  System.Windows.Controls.DockPanel.SetDock(sb, System.Windows.Controls.Dock.Top);
  sb.SnapsToDevicePixels := true;
  sb.Minimum := -1;
  sb.Maximum := all_removables.Count-1;
  sb.Value := sb.Minimum;
  sb.ValueChanged += (o,e)->
  begin
    rem_ind := e.NewValue.Round;
    UpdateContent;
  end;
  
  w.KeyDown += (o,e)->
  if e.Key = System.Windows.Input.Key.Back then
  begin
    sb.Value := rem_ind-1;
  end else
  if e.Key = System.Windows.Input.Key.Enter then
  begin
    sb.Value := rem_ind+1;
  end else
    ;
  
  
  
  Halt( System.Windows.Application.Create.Run(w) );
  
except
  on e: Exception do
    Writeln(e);
end;