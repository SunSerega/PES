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
    public event ReportNewError: TestResult->();
    
    protected stage_part_dir: string;
    protected expected_tr: TestResult;
    
    public constructor(stage_dir: string; expected_tr: TestResult);
    begin
      self.stage_part_dir := System.IO.Path.Combine(stage_dir, self.GetType.Name);
      self.expected_tr := expected_tr;
    end;
    private constructor := raise new System.InvalidOperationException;
    
    protected function MakeMinimizable(dir, target: string): MinimizableContainer; abstract;
    protected procedure OnCounterCreated(counter: MinimizationCounter); abstract;
    public function Execute(last_source_dir: string): string;
    begin
      Result := last_source_dir;
      
      var StagePartStarted := self.StagePartStarted;
      if StagePartStarted<>nil then StagePartStarted();
      
      var minimizable := MakeMinimizable(last_source_dir, expected_tr.SourceFName);
      minimizable.UnWrapTo( System.IO.Path.Combine(stage_part_dir, '0'), nil );
      ReportLineCount(minimizable.CountLines(nil));
      
      var counter := new MinimizationCounter(minimizable, expected_tr, self.stage_part_dir, (curr_test_dir, ti)->
      begin
        var final_tr: TestResult;
        var res: boolean;
        
        var ctr := new CompResult(expected_tr, curr_test_dir);
        final_tr := ctr;
        if self.expected_tr is CompResult(var expected_ctr) then
          res := CompResult.AreSame(ctr, expected_ctr) else
        if ctr.IsError then
          res := false else
        begin
          var etr := new ExecResult(ctr);
          final_tr := etr;
          if self.expected_tr is ExecResult(var expected_etr) then
            res := ExecResult.AreSame(etr, expected_etr) else
          begin
            raise new System.NotSupportedException(expected_tr.GetType.ToString);
          end;
        end;
        
        if not res then ReportNewError(final_tr);
        Result := (final_tr, res);
      end);
      
      counter.ReportLineCount += line_count->self.ReportLineCount(line_count);
      OnCounterCreated(counter);
      
      if counter.Execute then
        Result := counter.LastStableDir;
      
    end;
    
    public function MakeUIElement: System.Windows.UIElement; abstract;
    public function MakeTestUIElement(m: MinimizableContainer; rti: RemTestInfo): System.Windows.UIElement; abstract;
    
  end;
  
end.