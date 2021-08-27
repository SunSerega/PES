unit MSPFileParser;
{$string_nullbased+}

uses System.Windows;
uses System.Windows.Controls;
uses System.Windows.Media;

uses VUtils           in '..\VUtils';
uses Common           in '..\Common';

uses MinimizableCore  in '..\..\Backend\MinimizableCore';
uses MFileParser      in '..\..\Backend\Minimizables\MFileParser';
uses Testing          in '..\..\Backend\Testing';

uses MSPStandard;

type
  CodeChangesWindow = sealed class(ScrollViewer)
    
    private static function CalculateTextXY(l: List<integer>; var x: integer): integer;
    begin
      Result := 0;
      
      var l_ind := 0;
      while (l_ind<l.Count) and (l[l_ind] < x) do l_ind += 1;
      if l_ind=0 then exit;
      
      Result := l_ind;
      l_ind -= 1;
      x -= l[l_ind]+1;
      
    end;
    
    public constructor(text: string; deleted: List<SIndexRange>; added: List<AddedText>; GetIndexAreas: StringIndex->List<SIndexRange>);
    begin
      if text.Length=0 then exit;
//      self.Background := Brushes.White;
      self.VerticalScrollBarVisibility := ScrollBarVisibility.Auto;
      self.HorizontalScrollBarVisibility := ScrollBarVisibility.Auto;
      
      var sh := new StackedHeap;
      self.Content := sh;
      
      var tb := new TextBlock;
      sh.Children.Add(tb);
      tb.Text := text;
      tb.FontFamily := new System.Windows.Media.FontFamily('Courier New');
      
      var ft := new FormattedText('a', System.Globalization.CultureInfo.CurrentCulture, tb.FlowDirection, new Typeface(tb.FontFamily, tb.FontStyle, tb.FontWeight, tb.FontStretch), tb.FontSize, Brushes.Black);
      var w := ft.Width;
      var h := ft.Height;
      
      var cv := new Canvas;
      sh.Children.Add(cv);
      
      var line_break_inds := new List<integer>;
      for var i := 0 to text.Length-1 do
        if text[i]=#10 then
          line_break_inds += i;
      line_break_inds += text.Length;
      
      var corner_w := 1;
      var make_overlay := function(x1,y1, x2,y2: integer; c: Color): UIElement->
      begin
        
        if y1>=y2 then
        begin
          
          var highligher := new Border;
          highligher.BorderBrush := new SolidColorBrush(c);
          highligher.BorderThickness := new Thickness(2);
          highligher.Background := new SolidColorBrush(Color.FromArgb(64, c.R,c.G,c.B));
          highligher.CornerRadius := new CornerRadius(corner_w);
          highligher.Width := ((x2<x1) or (y2<y1) ? 0 : (x2-x1)*w) + corner_w*2;
          highligher.Height := h + corner_w*2;
          Canvas.SetLeft(highligher, x1*w-corner_w);
          Canvas.SetTop (highligher, y1*h-corner_w);
          
          highligher.IsHitTestVisible := false;
          Result := highligher;
        end else
        begin
          var ww := System.Windows.SystemParameters.PrimaryScreenWidth;
          
          var highligher := new PathFigure(
            new Point(x1*w-corner_w, (y1+1)*h),
            new PathSegment[](
              new LineSegment (new Point(x1*w-corner_w, y1*h), true),
              new ArcSegment  (new Point(x1*w, y1*h-corner_w), new Size(corner_w, corner_w), 0, false, SweepDirection.Clockwise, true),
              new LineSegment (new Point(ww, y1*h-corner_w), true),
              new LineSegment (new Point(ww, y2*h), true),
              new LineSegment (new Point(x2*w+corner_w, y2*h), true),
              new LineSegment (new Point(x2*w+corner_w, (y2+1)*h), true),
              new ArcSegment  (new Point(x2*w, (y2+1)*h+corner_w), new Size(corner_w, corner_w), 0, false, SweepDirection.Clockwise, true),
              new LineSegment (new Point(0, (y2+1)*h+corner_w), true),
              new ArcSegment  (new Point(0-corner_w, (y2+1)*h), new Size(corner_w, corner_w), 0, false, SweepDirection.Clockwise, true),
              new LineSegment (new Point(0-corner_w, (y1+1)*h), true)
            ), true
          );
          
          var path := new System.Windows.Shapes.Path;
          path.Data := new PathGeometry(|highligher|);
          path.Stroke := new SolidColorBrush(c);
          path.StrokeThickness := 2;
          path.Fill := new SolidColorBrush(Color.FromArgb(32, c.R,c.G,c.B));
          
          path.IsHitTestVisible := false;
          Result := path;
        end;
        
      end;
      var make_range_overlay := function(range: SIndexRange; c: Color): UIElement->
      begin
        
        var x1 := integer(range.i1);
        var y1 := CalculateTextXY(line_break_inds, x1);
        
        var x2 := integer(range.i2);
        var y2 := CalculateTextXY(line_break_inds, x2);
        
//        line_break_inds.Take(10).Println;
//        $'range={range} x1={x1} y1={y1} x2={x2} y2={y2}'.Println;
        Result := make_overlay(x1,y1, x2,y2, c);
      end;
      
      {$region Changed}
      var first_change_ind := StringIndex.Invalid;
      
      //ToDo #2480
      var d := default(SIndexRange);
      foreach d in deleted do
      begin
        if first_change_ind.IsInvalid or (d.i1 < first_change_ind) then
          first_change_ind := d.i1;
        cv.Children.Add( make_range_overlay(d, Color.FromRgb(255,0,0)) );
      end;
      
      //ToDo #2480
      var a := default(AddedText);
      foreach a in added do
      begin
        if first_change_ind.IsInvalid or (a.ind < first_change_ind) then
          first_change_ind := a.ind;
        
        var x := integer(a.ind);
        var y := CalculateTextXY(line_break_inds, x);
        
        cv.Children.Add( make_overlay(x,y, x,y, Color.FromRgb(0,255,0)) );
        
//        var highligher := new Border;
//        cv.Children.Add(highligher);
//        highligher.BorderBrush := new SolidColorBrush(Color.FromArgb(255, 0,255,0));
//        highligher.BorderThickness := new Thickness(1);
//        highligher.Background := new SolidColorBrush(Color.FromArgb(128, 0,255,0));
//        highligher.CornerRadius := new CornerRadius(corner_w);
//        highligher.Width := corner_w*2;
//        highligher.Height := h+corner_w*2;
//        Canvas.SetLeft(highligher, x*w-corner_w);
//        Canvas.SetTop (highligher, y*h-corner_w);
        
      end;
      
      if not first_change_ind.IsInvalid then
      begin
        var x := integer(first_change_ind);
        var y := CalculateTextXY(line_break_inds, x);
        self.ScrollToVerticalOffset(h*y-5);
      end;
      {$endregion Changed}
      
      {$region GetIndexAreas}
      
      var PrevIndexAreas := new List<UIElement>;
      self.MouseMove += (o,e)->
      begin
        foreach var el in PrevIndexAreas do
          cv.Children.Remove(el);
        PrevIndexAreas.Clear;
        
        var p := e.GetPosition(cv);
        var y := Trunc(p.Y/h);
        
        if y>=line_break_inds.Count then exit;
        var prev_lines_ch_count := if y=0 then 0 else line_break_inds[y-1]+1;
        
        var x := Trunc(p.X/w).ClampTop( line_break_inds[y] - prev_lines_ch_count );
//        Println(x, y, prev_lines_ch_count);
        
        var ToDo := 0; //ToDo #2480
        var range := default(SIndexRange);
        foreach range in GetIndexAreas(x + prev_lines_ch_count) do
        begin
//          Writeln(range);
          var el := make_range_overlay(range, Color.FromRgb(0,0,255));
          PrevIndexAreas += el;
          cv.Children.Add(el);
        end;
        
      end;
      self.MouseLeave += (o,e)->
      begin
        foreach var el in PrevIndexAreas do
          cv.Children.Remove(el);
        PrevIndexAreas.Clear;
      end;
      
      {$endregion GetIndexAreas}
      
    end;
    
  end;
  
  ParserTestUI = sealed class(TabControl, ITestResultApplyable)
    private head_sp := new StackPanel;
    
    public procedure ApplyTestResult(tr: TestResult; res: boolean);
    begin
      
      var trv := new TestResultViewer(tr, nil);
      head_sp.Children.Insert(0, trv);
      trv.BorderThickness := new Thickness(2);
      trv.BorderBrush := if res then Brushes.DarkGreen else Brushes.DarkRed;
      
    end;
    
    public constructor(m: MFileBatch; rti: RemTestInfo);
    begin
      
      var LinesRemovedSP := new StackPanel;
      begin
        var head_item := new TabItem;
        self.Items.Add(head_item);
        head_item.Header := 'Metadata';
        head_item.Content := head_sp;
        
        var tb1 := new TextBlock;
        head_sp.Children.Add(tb1);
        tb1.Text := 'Lines removed:';
        
        head_sp.Children.Add(LinesRemovedSP);
        
        var b1 := new Button;
        head_sp.Children.Add(b1);
        b1.Content := 'UnWrap';
        b1.BorderThickness := new Thickness(1);
        b1.BorderBrush := Brushes.Black;
        b1.Click += (o,e)->
        begin
          var dir := 1.Step(1).Select(i->$'UnWraped_{i}').SkipWhile(System.IO.Directory.Exists).First;
          //ToDo Тут и в m.ForEachParsed - m вполне может быть устаревшим, на котором провели .Cleanup следующего слоя
          m.UnWrapTo(dir, rti.NeedNode);
          Exec(dir);
        end;
        
      end;
      
      m.ForEachParsed(f->
      begin
        var sw := new System.IO.StringWriter;
        f.UnWrapTo(sw, rti.Parent.NeedNode);
        var text := sw.ToString;
        
        //ToDo Сюда и в f.GetIndexAreas надо передавать и rti.Parent.NeedNode, и rti.NeedNode
        var (deleted, added) := f.GetChangedSections(rti.NeedNode);
        
        if deleted.Any or added.Any then
        begin
          var tb := new TextBlock;
          LinesRemovedSP.Children.Add(tb);
          var c := text.CountOf(#10)+1 - f.CountLines(rti.NeedNode);
          tb.Text := $'{f.PrintableName}: {c}';
        end;
        
        var file_item := new TabItem;
        self.Items.Add(file_item);
        file_item.Header := f.PrintableName;
        file_item.Content := new CodeChangesWindow(text, deleted, added, f.GetIndexAreas);
        
      end);
      
    end;
    
  end;
  
  FileParserMSP = sealed class(StandardMSP)
    
    protected function MakeMinimizable(dir, target: string): MinimizableContainer; override :=
    new MFileBatch(dir, target);
    
    protected property Description: string read 'Parsed item removal'; override;
    
    public function MakeTestUIElement(m: MinimizableContainer; rti: RemTestInfo): System.Windows.UIElement; override :=
    new ParserTestUI(MFileBatch(m), rti);
    
  end;
  
end.