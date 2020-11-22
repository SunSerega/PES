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
      
      var minimizable := MakeMinimizable(last_source_dir);
      minimizable.UnWrapTo( System.IO.Path.Combine(stage_part_dir, '0') );
      ReportLineCount(minimizable.CountLines(nil));
      
      var counter := new MinimizationCounter(minimizable, self.stage_part_dir, (curr_test_dir,ti)->
      begin
        
        var ctr := new CompResult(expected_tr, curr_test_dir);
        if self.expected_tr is CompResult(var expected_ctr) then
          Result := CompResult.AreSame(ctr, expected_ctr) else
        if ctr.IsError then
          Result := false else
        begin
          var etr := new ExecResult(ctr);
          if self.expected_tr is ExecResult(var expected_etr) then
            Result := ExecResult.AreSame(etr, expected_etr) else
          begin
            raise new System.NotSupportedException(expected_tr.GetType.ToString);
          end;
        end;
        
        System.IO.Directory.Delete(curr_test_dir, true);
      end);
      
      counter.ReportLineCount += line_count->self.ReportLineCount(line_count);
      OnCounterCreated(counter);
      
      if counter.Execute then
        Result := counter.LastStableDir;
      
    end;
    
    public function MakeUIElement: System.Windows.UIElement; abstract;
    
  end;
  
end.