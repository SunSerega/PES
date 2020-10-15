unit Minimization;

uses System.Windows;
uses System.Windows.Controls;
uses System.Windows.Media;

uses PathUtils    in '..\Utils\PathUtils';

uses Testing      in '..\Backend\Testing';
uses SettingData  in '..\Backend\SettingData';

uses VUtils;
uses Common;

type
  
  MinimizationStagePart = abstract class
    public any_change := false;
    
    private stage_part_dir: string;
    
    public constructor(stage_dir: string);
    begin
      self.stage_part_dir := System.IO.Path.Combine(stage_dir, self.GetType.Name);
      
    end;
    private constructor := raise new System.InvalidOperationException;
    
    public function Execute(last_source_dir: string): string; abstract;
    
    public function MakeUIElement: UIElement; abstract;
    
  end;
  FileRemoveMSP = sealed class(MinimizationStagePart)
    
    public function Execute(last_source_dir: string): string; override;
    begin
      Result := last_source_dir;
      
      CopyDir(last_source_dir, stage_part_dir);
      Result := stage_part_dir;
      Sleep(1000);
      var ToDo := 0;
      
    end;
    
    public function MakeUIElement: UIElement; override;
    begin
      var res := new TextBlock;
      Result := res;
      res.Text := stage_part_dir;
      var ToDo := 0;
      
    end;
    
  end;
  
  MinimizationStage = sealed class(Border)
    public event StagePartDone: string->();
    
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
    
    public constructor(stage_num: integer; work_dir: string);
    begin
      self.stage_num := stage_num;
      self.stage_dir := System.IO.Path.Combine(work_dir, stage_num.ToString);
      
      self.BorderBrush := new SolidColorBrush(Colors.Black);
      self.BorderThickness := new Thickness(1);
      self.Margin := new Thickness(10,10,10,0);
      self.Background := new SolidColorBrush(Color.FromRgb(240,240,240));
      
      self.Child := sr;
      
      var spoiler_sp := new StackPanel;
      sr.Content := spoiler_sp;
      
      var spoiler_title := new ClickableTextBlock;
      spoiler_sp.Children.Add(spoiler_title);
      spoiler_title.Text := $'Stage {stage_num}';
      spoiler_title.Margin := new Thickness(5);
      spoiler_title.HorizontalAlignment := System.Windows.HorizontalAlignment.Stretch;
      
      spoiler_sp.Children.Add(stage_parts_sp);
      stage_parts_sp.Margin := new Thickness(5,0,5,5);
      spoiler_title.Click += (o,e)->
      begin
        spoiler_opened := not spoiler_opened;
        ValidateSpoiler;
        spoiler_clicked := true;
      end;
      
    end;
    private constructor := raise new System.InvalidOperationException;
    
    private function ApplyMSP(last_source_dir: string; msp: MinimizationStagePart): string;
    begin
      Dispatcher.Invoke(()->
      begin
        self.stage_parts_sp.Children.Add(msp.MakeUIElement);
        Application.Current.MainWindow.Title := $'PES: Stage={stage_num}, stage_part={msp.GetType.Name}';
      end);
      var new_source_dir := msp.Execute(last_source_dir);
      if last_source_dir<>new_source_dir then
      begin
        StagePartDone(new_source_dir);
        Result := new_source_dir;
      end else
        Result := last_source_dir;
    end;
    
    public function Execute(last_source_dir: string): string;
    begin
      Result := last_source_dir;
      
      Result := ApplyMSP(Result, new FileRemoveMSP(self.stage_dir));
      var ToDo := 0;
      
    end;
    
  end;
  
  MinimizationLog = sealed class(Border)
    public event StagePartDone: string->();
    
    public constructor(inital_state_dir: string);
    begin
      self.BorderThickness := new Thickness(0,0,1,0);
      self.BorderBrush := Brushes.Black;
      
      var svsbsr := new SmoothResizer;
      self.Child := svsbsr;
      svsbsr.SmoothY := false;
      
      var sv := new ScrollViewer;
      svsbsr.Content := sv;
      sv.VerticalScrollBarVisibility := ScrollBarVisibility.Auto;
      sv.VerticalAlignment := System.Windows.VerticalAlignment.Top;
      sv.Padding := new Thickness(5);
      
      var sr := new SmoothResizer;
      sv.Content := sr;
      sr.SmoothX := false;
      
      var sp := new StackPanel;
      sr.Content := sp;
      
      System.Threading.Thread.Create(()->
      try
        var i := 1;
        var last_source_dir := inital_state_dir;
        var work_dir := System.IO.Path.GetDirectoryName(last_source_dir);
        var prev_ms := default(MinimizationStage);
        
        while true do
        begin
          var ms := sp.Dispatcher.Invoke(()->
          begin
            Result := new MinimizationStage(i, work_dir);
            if prev_ms<>nil then Result.sr.SnapX(w->Min(prev_ms.sr.ExtentSize.Width, w));
            sp.Children.Add(Result);
          end);
          
          ms.StagePartDone += dir->self.StagePartDone(dir);
          var new_source_dir := ms.Execute(last_source_dir);
          
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
      end).Start;
      
    end;
    private constructor := raise new System.InvalidOperationException;
    
  end;
  
  LinesLeftGraph = sealed class(Border)
    private static LinesLeftProp := DependencyProperty.Register('LinesLeft', typeof(real), typeof(LinesLeftGraph), new FrameworkPropertyMetadata(0.0, FrameworkPropertyMetadataOptions.AffectsArrange));
    private property LinesLeft: real read real(GetValue(LinesLeftProp));// write SetValue(LinesLeftProp, value);
    
    private rects := new Border[0];
    private cross := new System.Windows.Shapes.Line[2];
    private descr := new TextBlock[4];
    
    public constructor(get_lines_target: ()->real);
    begin
      self.BeginAnimation(LinesLeftProp, new SmoothDoubleAnimation(get_lines_target(), get_lines_target, 0, 0.5));
      
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
      // l    : Размер квадрата в пикселях
      
      var val_1px_pow :=  LogN(sqrt(2), val*2/l);
      var val_l_pow :=    LogN(sqrt(2), val*2);
      
      var shift := val_1px_pow-System.Math.Floor(val_1px_pow);
      var rect_c := Floor((val_l_pow-val_1px_pow) - shift);
      
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
      var conv_k := val/l;
      var curr_rect_val1 := sqrt(2)**(System.Math.Floor(val_pow)+1) / conv_k;
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
          t.Text := (curr_rect_val1*conv_k).Round.ToString;
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
  
  MinimizationViewer = sealed class(DockPanel)
    
    private static function CountLines(dir: string) :=
    EnumerateAllFiles(dir, '*.pas').Sum(fname->ReadLines(fname).Count);
    
    public constructor(inital_state_dir: string; tr: TestResult);
    begin
      
//      var lines_count := 0.0;
      var lines_count := CountLines(inital_state_dir);
      
      begin
        var log := new MinimizationLog(inital_state_dir);
        self.Children.Add(log);
        log.StagePartDone += dir->
        begin
          lines_count := CountLines(dir);
//          lines_count *= 1.2;
//          lines_count -= 1;
        end;
      end;
      
      begin
        var graph_dp := new DockPanel;
        self.Children.Add(graph_dp);
        graph_dp.HorizontalAlignment := System.Windows.HorizontalAlignment.Left;
        
        var trv := new TestResultViewer(tr, nil);
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