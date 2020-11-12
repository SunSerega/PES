unit MSPCore;

uses VUtils     in '..\VUtils';
uses PathUtils  in '..\..\Utils\PathUtils';
uses Testing    in '..\..\Backend\Testing';
uses Counters   in '..\..\Backend\Counters';

uses MinimizableCore  in '..\..\Backend\MinimizableCore';

type
  MinimizationStagePart = abstract class
    public event StagePartStarted: Action0;
    public event ReportLineCount: integer->();
    
    protected stage_part_dir: string;
    protected expected_tr: TestResult;
    
    public constructor(stage_dir: string; expected_tr: TestResult);
    begin
      self.stage_part_dir := System.IO.Path.Combine(stage_dir, self.GetType.Name);
      self.expected_tr := expected_tr;
    end;
    private constructor := raise new System.InvalidOperationException;
    
    protected function MakeMinimizable(dir: string): MinimizableList; abstract;
    protected procedure OnCounterCreated(counter: MinimizationCounter); abstract;
    public function Execute(last_source_dir: string): string;
    begin
      Result := last_source_dir;
      
      var StagePartStarted := self.StagePartStarted;
      if StagePartStarted<>nil then StagePartStarted();
      
      var temp_source_origin := System.IO.Path.Combine(stage_part_dir, '0');
      CopyDir(last_source_dir, temp_source_origin);
      var minimizable := MakeMinimizable(temp_source_origin);
      ReportLineCount(minimizable.CountLines(nil));
      
      var counter := new MinimizationCounter(minimizable, self.stage_part_dir, curr_test_dir->
      begin
        var final_tr: TestResult;
        
        var ctr := new CompResult(expected_tr, curr_test_dir);
        final_tr := ctr;
        if self.expected_tr is CompResult(var expected_ctr) then
          Result := CompResult.AreSame(ctr, expected_ctr) else
        if ctr.IsError then
          Result := false else
        begin
          var etr := new ExecResult(ctr);
          final_tr := etr;
          if self.expected_tr is ExecResult(var expected_etr) then
            Result := ExecResult.AreSame(etr, expected_etr) else
          begin
            raise new System.NotSupportedException(expected_tr.GetType.ToString);
          end;
        end;
        
        try
          foreach var fname in EnumerateFiles(curr_test_dir) do System.IO.File.Delete(fname);
          foreach var sub_dir in EnumerateDirectories(curr_test_dir) do System.IO.Directory.Delete(sub_dir, true);
        except
          on e: Exception do
          begin
            curr_test_dir.Println;
            Writeln(e);
            Halt;
          end;
        end;
        
        begin
          var new_curr_test_dir := System.IO.Path.Combine(
            System.IO.Path.GetDirectoryName(curr_test_dir),
            (Result?'+ ':'- ') + System.IO.Path.GetFileName(curr_test_dir)
          );
          System.IO.Directory.Move(curr_test_dir, new_curr_test_dir);
          curr_test_dir := new_curr_test_dir;
        end;
        
        final_tr.ReportTo(curr_test_dir);
      end);
      
      counter.ReportLineCount += line_count->self.ReportLineCount(line_count);
      OnCounterCreated(counter);
      
      if counter.Execute then
      begin
        Result := System.IO.Path.Combine(stage_part_dir, '0-res');
        minimizable.UnWrapTo(Result);
      end;
      
    end;
    
    public function MakeUIElement: System.Windows.UIElement; abstract;
    
  end;
  
end.