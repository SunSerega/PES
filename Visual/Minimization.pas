unit Minimization;

uses System.Windows;
uses System.Windows.Controls;
uses System.Windows.Media;

uses SettingData  in '..\Backend\SettingData';
uses Testing      in '..\Backend\Testing';

uses VUtils;
uses Common;

uses MSPCore        in 'MSP\MSPCore';
uses MSPFolder      in 'MSP\MSPFolder';
uses MSPFileParser  in 'MSP\MSPFileParser';

type
  
  MinimizationStage = sealed class(Border)
    public event StagePartStarted: Action0;
    public event ReportLineCount: integer->();
    public event ReportNewError: TestResult->();
    
    private stage_num: integer;
    private stage_dir: string;
    
    private sr := new SmoothResizer;
    
    private stage_parts_sp := new StackPanel;
    private spoiler_opened := true;
    private spoiler_clicked := false;
    
    private procedure ValidateSpoiler;
    begin
      stage_parts_sp.Visibility := spoiler_opened ?
        System.Windows.Visibility.Visible :
        System.Windows.Visibility.Collapsed;
    end;
    
    public constructor(stage_num: integer);
    begin
      self.stage_num := stage_num;
      self.stage_dir := System.IO.Path.Combine(test_dir, stage_num.ToString);
      
      self.BorderBrush := new SolidColorBrush(Colors.Black);
      self.BorderThickness := new Thickness(1);
      self.Margin := new Thickness(10,10,10,0);
      self.Background := new SolidColorBrush(Color.FromRgb(240,240,240));
      
      self.Child := sr;
      sr.SmoothX := true;
      sr.SmoothY := true;
      sr.FillX := false;
      sr.HorizontalAlignment := System.Windows.HorizontalAlignment.Left;
      
      var spoiler_sp := new StackPanel;
      sr.Content := spoiler_sp;
      
      var spoiler_title := new ClickableContent;
      spoiler_sp.Children.Add(spoiler_title);
      spoiler_title.Margin := new Thickness(5);
      spoiler_title.Click += (o,e)->
      begin
        spoiler_opened := not spoiler_opened;
        ValidateSpoiler;
        spoiler_clicked := true;
      end;
      
      var spoiler_title_tb := new TextBlock;
      spoiler_title.Content := spoiler_title_tb;
      spoiler_title_tb.Text := $'Stage {stage_num}';
      spoiler_title_tb.HorizontalAlignment := System.Windows.HorizontalAlignment.Stretch;
      
      spoiler_sp.Children.Add(stage_parts_sp);
      stage_parts_sp.Margin := new Thickness(5,0,5,5);
      
    end;
    private constructor := raise new System.InvalidOperationException;
    
    private function ApplyMSP(last_source_dir: string; msp: MinimizationStagePart): string;
    begin
      msp.ReportLineCount += line_count->self.ReportLineCount(line_count);
      Dispatcher.Invoke(()->
      begin
        var msp_visual := msp.MakeUIElement;
        self.stage_parts_sp.Children.Add(msp_visual);
        Application.Current.MainWindow.Title := $'PES: Stage={stage_num}, stage_part={msp.GetType.Name}';
      end);
      msp.ReportNewError += self.ReportNewError;
      msp.StagePartStarted += ()->
      begin
        var StagePartStarted := self.StagePartStarted;
        if StagePartStarted<>nil then
        begin
          self.StagePartStarted -= StagePartStarted;
          StagePartStarted();
        end;
      end;
      Result := msp.Execute(last_source_dir);
    end;
    
    public function Execute(last_source_dir: string; expected_tr: TestResult): string;
    begin
      Result := last_source_dir;
      
      Result := ApplyMSP(Result, new     FolderMSP(self.stage_dir, expected_tr));
      Result := ApplyMSP(Result, new FileParserMSP(self.stage_dir, expected_tr));
      
    end;
    
  end;
  
  MinimizationLog = sealed class(Border)
    public event ReportLineCount: integer->();
    public event ReportNewError: TestResult->();
    
    private thr: System.Threading.Thread;
    public constructor(inital_state_dir: string; expected_tr: TestResult);
    begin
      self.BorderThickness := new Thickness(0,0,1,0);
      self.BorderBrush := Brushes.Black;
      
      var svsbsr := new SmoothResizer;
      self.Child := svsbsr;
      svsbsr.SmoothX := true;
      svsbsr.FillX := false;
      svsbsr.HorizontalAlignment := System.Windows.HorizontalAlignment.Left;
      
      var sv := new ScrollViewer;
      svsbsr.Content := sv;
      sv.VerticalScrollBarVisibility := ScrollBarVisibility.Auto;
      sv.VerticalAlignment := System.Windows.VerticalAlignment.Top;
      sv.Padding := new Thickness(5);
      
      var sp := new StackPanel;
      sv.Content := sp;
      
      self.thr := new System.Threading.Thread(()->
      try
        var i := 1;
        var last_source_dir := inital_state_dir;
        var prev_ms := default(MinimizationStage);
        
        while true do
        begin
          var sp := sp; //ToDo #2344
          
          var ms := sp.Dispatcher.Invoke(()->new MinimizationStage(i));
          
          ms.StagePartStarted += ()->sp.Dispatcher.Invoke(()->sp.Children.Add(ms));
          ms.ReportLineCount += self.ReportLineCount;
          ms.ReportNewError += self.ReportNewError;
          var new_source_dir := ms.Execute(last_source_dir, expected_tr);
          
          Dispatcher.Invoke(()->
          if (prev_ms<>nil) and not prev_ms.spoiler_clicked then 
          begin
            prev_ms.spoiler_opened := false;
            prev_ms.ValidateSpoiler;
          end);
          prev_ms := ms;
          
          if new_source_dir=last_source_dir then break;
          last_source_dir := new_source_dir;
          
          i += 1;
        end;
        
        Exec(last_source_dir);
        Dispatcher.Invoke(()->
        begin
          Application.Current.MainWindow.Title := $'PES: Done';
        end);
      except
        on e: Exception do
        begin
          MessageBox.Show(e.ToString);
          Halt;
//          break;
        end;
      end);
      
    end;
    private constructor := raise new System.InvalidOperationException;
    
    public procedure Start := thr.Start;
    
  end;
  
  LinesLeftGraph = sealed class(Border)
    private static LinesLeftProp := DependencyProperty.Register('LinesLeft', typeof(real), typeof(LinesLeftGraph), new FrameworkPropertyMetadata(0.0, FrameworkPropertyMetadataOptions.AffectsArrange));
    private property LinesLeft: real read real(GetValue(LinesLeftProp));// write SetValue(LinesLeftProp, value);
    
    private rects := new Border[0];
    private cross := new System.Windows.Shapes.Line[2];
    private descr := new TextBlock[4];
    
    public constructor(get_lines_target: ()->real);
    begin
      self.BeginAnimation(LinesLeftProp, new SmoothDoubleAnimation(get_lines_target(), get_lines_target, 0, 0.4));
      
      self.BorderBrush := new SolidColorBrush(Colors.Black);
      self.BorderThickness := new Thickness(1);
      self.Margin := new Thickness(10);
      self.ClipToBounds := true;
      
      cross[0] := new System.Windows.Shapes.Line;
      self.AddLogicalChild(cross[0]);
      self.AddVisualChild(cross[0]);
      cross[0].Stroke := new SolidColorBrush(Colors.DarkRed);
      cross[0].StrokeThickness := 3;
      
      cross[1] := new System.Windows.Shapes.Line;
      self.AddLogicalChild(cross[1]);
      self.AddVisualChild(cross[1]);
      cross[1].Stroke := new SolidColorBrush(Colors.DarkRed);
      cross[1].StrokeThickness := 3;
      
      for var i := 0 to descr.Length-1 do
      begin
        var t := new TextBlock;
        descr[i] := t;
        t.Background := new SolidColorBrush(Color.FromRgb(240,240,240));
//        t.RenderTransformOrigin := new Point(0,1);
        self.AddLogicalChild(descr[i]);
        self.AddVisualChild(descr[i]);
      end;
      
    end;
    private constructor := raise new System.InvalidOperationException;
    
    private procedure ValidateRects(val, l: real);
    begin
      // val  : Текущее значение в центре квадрата
      // l    : Длина стороны квадрата в пикселях
      
      // Степень на уровне значения, которое будет соответствовать верхней границе квадрата
      var val_l_pow := LogN(Sqrt(2), val*2);
      // Степень на уровне значения, которое будет соответствовать одному пикселю
//      var val_1px_pow := LogN(Sqrt(2), val/(l/2) );
//      var val_1px_pow := LogN(Sqrt(2), val*2/l );
      var val_1px_pow := val_l_pow - LogN(Sqrt(2), l.ClampBottom(1)); // .Clamp потому что считать отрицательную (или даже NaN) разницу нет смысла
      
      // Надо принимать во внимание 2 вещи:
      // 1. В теории прямоугольников будет (val_l_pow-val_1px_pow), но надо применить Floor
      // 2. Первый прямоугольник будет не прямо на верхней границе, а немного под ней - на уровне Floor(val_l_pow)
      
      // .Clamp потому что если первый прямоугольник уже меньше 1 пикселя - рисовать надо 0 а не -1 прямоугольников
      var rect_c := Floor(System.Math.Floor(val_l_pow) - val_1px_pow).ClampBottom(0);
      
      var prev_rect_c := rects.Length;
      if prev_rect_c <> rect_c then
        if prev_rect_c < rect_c then
        begin
          SetLength(rects, rect_c);
          for var i := prev_rect_c to rect_c-1 do
          begin
            var r := new Border;
            rects[i] := r;
            self.AddLogicalChild(r);
            self.AddVisualChild(r);
            r.BorderThickness := new Thickness(1);
            r.BorderBrush := new SolidColorBrush(Colors.Black);
//            r.Background := new SolidColorBrush(Color.FromRgb(Random(256), Random(256), Random(256)));
          end;
        end else
        begin
          for var i := prev_rect_c-1 downto rect_c do
            self.RemoveVisualChild(rects[i]);
          SetLength(rects, rect_c);
        end;
      
    end;
    
    protected property VisualChildrenCount: integer read rects.Length + cross.Length + descr.Length; override;
    protected function GetVisualChild(ind: integer): Visual; override;
    begin
      if ind < rects.Length then
        Result := rects[ind] else
      begin
        ind -= rects.Length;
        if ind < cross.Length then
          Result := cross[ind] else
        begin
          ind -= cross.Length;
          if ind < descr.Length then
            Result := descr[ind] else
            raise new System.ArgumentOutOfRangeException;
        end;
      end;
    end;
    
    protected function MeasureOverride(availableSize: Size): Size; override;
    begin
      var l := Min(availableSize.Width, availableSize.Height);
      Result := new Size(l, l);
    end;
    
    protected function ArrangeOverride(finalSize: Size): Size; override;
    begin
      var l := Min(finalSize.Width, finalSize.Height);
      Result := new Size(l, l);
      
      cross[0].X1 := l/2;
      cross[0].X2 := l/2;
      cross[0].Y2 := l;
      cross[0].Arrange(new Rect(Result));
      
      cross[1].Y1 := l/2;
      cross[1].Y2 := l/2;
      cross[1].X2 := l;
      cross[1].Arrange(new Rect(Result));
      
      var val := LinesLeft;
      ValidateRects(val, l);
      
      var val_pow := LogN(sqrt(2), val);
      var flipped := System.Math.IEEERemainder(val_pow, 2) < 0; // IEEERemainder возвращает от -1 до 1
      var conv_k := val/(l/2);
      var curr_rect_val1 := sqrt(2)**(System.Math.Floor(val_pow)+3) / conv_k;
      var curr_rect_val2 := curr_rect_val1 / sqrt(2);
      for var i := 0 to rects.Length-1 do
      begin
        var next_rect_val := curr_rect_val1/2;
        
        if flipped then
          rects[i].Arrange(new Rect(
            0,              l-curr_rect_val1,
            curr_rect_val2, curr_rect_val1
          )) else
          rects[i].Arrange(new Rect(
            0,              l-curr_rect_val2,
            curr_rect_val1, curr_rect_val2
          ));
        
        if (i>=1) and (i-1 < descr.Length) then
        begin
          var t := descr[i-1];
          var lines_displayer := curr_rect_val1*conv_k;
          t.Text := lines_displayer.ToString('N'+(3-Floor(Log10(lines_displayer).ClampBottom(0)+1)).ClampBottom(0));
          t.RenderTransform := flipped ? new RotateTransform(90) : nil;
          t.Measure(new Size(real.PositiveInfinity, real.PositiveInfinity));
          if flipped then
            t.Arrange(new Rect(
              t.DesiredSize.Height+3, l-curr_rect_val1-t.DesiredSize.Width/2,
              t.DesiredSize.Width, t.DesiredSize.Height
            )) else
            t.Arrange(new Rect(
              curr_rect_val1-t.DesiredSize.Width/2, l-t.DesiredSize.Height-3,
              t.DesiredSize.Width, t.DesiredSize.Height
            ));
        end;
        
        flipped := not flipped;
        curr_rect_val1 := curr_rect_val2;
        curr_rect_val2 := next_rect_val;
      end;
      
    end;
    
  end;
  
  MinimizationViewer = sealed class(Grid)
    
    public constructor(inital_state_dir: string; tr: TestResult);
    begin
      
      var cd1 := new ColumnDefinition;
      cd1.Width := GridLength.Auto;
      self.ColumnDefinitions.Add(cd1);
      
      var cd2 := new ColumnDefinition;
      self.ColumnDefinitions.Add(cd2);
      
      var lines_count := 1.0;
//      var lines_count := CountLines(inital_state_dir);
      
      var error_list := new List<TestResult>;
      var NewErrorListItem: TestResult->();
      
      begin
        var log := new MinimizationLog(inital_state_dir, tr);
        self.Children.Add(log);
        Grid.SetColumn(log, 0);
        log.ReportLineCount += new_line_count->
        begin
          lines_count := new_line_count;
        end;
        log.ReportNewError += tr->
        lock error_list do
        begin
          if tr is CompResult(var ctr) then
          begin
            foreach var err in error_list.OfType&<CompResult> do
              if CompResult.AreSame(err, ctr) then
                exit;
          end else
          if tr is ExecResult(var etr) then
          begin
            foreach var err in error_list.OfType&<ExecResult> do
              if ExecResult.AreSame(err, etr) then
                exit;
          end else
            raise new System.NotSupportedException(tr.GetType.ToString);
          
          lock error_list do
          begin
            error_list += tr;
            
            error_list.Sort((tr1, tr2)->
            begin
              Result := 0;
              
              Result += integer(tr1 is ExecResult(var etr1));
              Result -= integer(tr2 is ExecResult(var etr2));
              if Result<>0 then exit;
              if etr1<>nil then
              begin
                Result := ExecResult.Compare(etr1, etr2);
                exit;
              end;
              
              Result += integer(tr1 is CompResult(var ctr1));
              Result -= integer(tr2 is CompResult(var ctr2));
              if Result<>0 then exit;
              if ctr1<>nil then
              begin
                Result := CompResult.Compare(ctr1, ctr2);
                exit;
              end;
              
              raise new System.NotSupportedException($'{tr1.GetType} ? {tr2.GetType}');
            end);
            
            var NewErrorListItem := NewErrorListItem;
            if NewErrorListItem<>nil then NewErrorListItem(tr);
          end;
          
        end;
        log.Start;
      end;
      
      begin
        var graph_dp := new DockPanel;
        self.Children.Add(graph_dp);
        Grid.SetColumn(graph_dp, 1);
        graph_dp.HorizontalAlignment := System.Windows.HorizontalAlignment.Left;
        
        var last_wrong_trs_window: Window;
        var last_wrong_trs_window_lock := new object;
        var trv := new TestResultViewer(tr, tr->
        begin
          var thr := new System.Threading.Thread(()->
          try
            var w := new Window;
            lock last_wrong_trs_window_lock do
            begin
              if last_wrong_trs_window<>nil then
              begin
                last_wrong_trs_window.Dispatcher.Invoke(last_wrong_trs_window.Activate);
                exit;
              end;
              last_wrong_trs_window := w;
            end;
            w.Closing += (o,e)->lock last_wrong_trs_window_lock do
            begin
              last_wrong_trs_window := nil;
              NewErrorListItem := nil;
            end;
            w.Title := 'All wrong test results';
            
            var sv := new ScrollViewer;
            w.Content := sv;
            sv.VerticalScrollBarVisibility := ScrollBarVisibility.Auto;
            sv.HorizontalScrollBarVisibility := ScrollBarVisibility.Auto;
            
            var sp := new StackPanel;
            sv.Content := sp;
            
            var MakeTRViewer := function(tr: TestResult): TestResultViewer->
            //ToDo Запускать новый PES для этого результата, а не nil
            new TestResultViewer(tr, nil);
            
            lock error_list do
            begin
              foreach var tr in error_list do
                sp.Children.Add(MakeTRViewer(tr));
              NewErrorListItem := tr->sp.Dispatcher.Invoke(()->
                sp.Children.Insert(error_list.IndexOf(tr), MakeTRViewer(tr))
              );
            end;
            
            w.KeyUp += (ko,ke)->if ke.Key = System.Windows.Input.Key.Escape then w.Close;
            w.Show;
            System.Windows.Threading.Dispatcher.Run;
          except
            on e: Exception do
              MessageBox.Show(e.ToString);
          end);
          thr.ApartmentState := System.Threading.ApartmentState.STA;
          thr.IsBackground := true;
          thr.Start;
        end);
        graph_dp.Children.Add(trv);
        DockPanel.SetDock(trv, Dock.Bottom);
        trv.Margin := new Thickness(5,0,5,5);
        
        var llg := new LinesLeftGraph(()->lines_count);
        graph_dp.Children.Add(llg);
        llg.HorizontalAlignment := System.Windows.HorizontalAlignment.Left;
        
      end;
      
    end;
    
  end;
  
end.