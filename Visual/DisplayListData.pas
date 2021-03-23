unit DisplayListData;

uses System.Windows;
uses System.Windows.Media;
uses System.Windows.Shapes;
uses System.Windows.Controls;

uses VUtils;

type
  
  __DisplayListItem<T> = sealed class(ContentControl)
  where T: FrameworkElement;
    public el: T;
    public anchor: FrameworkElement;
    
    public logical_y := real.NaN;
    private next_logical_y: real;
    private static VisualYProp := DependencyProperty.Register('VisualYProp', typeof(real), typeof(__DisplayListItem<T>), new FrameworkPropertyMetadata(0.0, FrameworkPropertyMetadataOptions.AffectsParentMeasure));
    public property VisualY: real read real( self.GetValue(VisualYProp) );
    
    public constructor(el: T; anchor: FrameworkElement);
    begin
      self.el     := el;
      self.anchor := anchor;
      
      self.Content := el;
      
    end;
    private constructor := raise new System.InvalidOperationException;
    
    public procedure StartAnimatingY(from: real);
    begin
      self.SetValue(VisualYProp, from);
      self.BeginAnimation(VisualYProp, new SmoothDoubleAnimation(from, ()->self.logical_y));
    end;
    
    public procedure ComfirmRealY :=
    self.logical_y := self.next_logical_y;
    
    public procedure UnDisplay;
    begin
      logical_y := real.NaN;
      self.BeginAnimation(VisualYProp, nil);
    end;
    
  end;
  
  __DisplayListContents<T> = sealed class(FrameworkElement)
  where T: FrameworkElement;
    public const MaxTintSize = 0.1; // * finalSize.Height
    
    private should_render_item: T->boolean;
    private new_scroll := 0.0;
    
    public constructor(should_render_item: T->boolean);
    begin
      self.should_render_item := should_render_item;
      self.MouseWheel += (o,e)->
      begin
        new_scroll += e.Delta;
        self.InvalidateMeasure;
        e.Handled := true;
      end;
      self.ClipToBounds := true;
    end;
    private constructor := raise new System.InvalidOperationException;
    
    private items := new List<__DisplayListItem<T>>;
    private max_items_height := 0.0;
    private last_item_pinned := false;
    public procedure AddItem(item: __DisplayListItem<T>);
    begin
      Dispatcher.VerifyAccess;
      if last_item_pinned and should_render_item(item.el) then
      begin
        var prev_pinn := items[pinned_item_ind.Value];
        item.logical_y := prev_pinn.logical_y;
        item.StartAnimatingY( prev_pinn.VisualY + prev_pinn.DesiredSize.Height );
        pinned_item_ind := items.Count;
      end;
      self.items += item;
      self.AddLogicalChild(item);
      self.InvalidateMeasure;
    end;
    
    public item_lines_y := new List<real>;
    private pinned_item_ind: integer? := nil;
    private displayed_items := new List<integer>;
    
    {$region Visual children}
    
    protected property VisualChildrenCount: integer read displayed_items.Count; override;
    protected function GetVisualChild(ind: integer): Visual; override := items[displayed_items[ind]];
    
    {$endregion Visual children}
    
    {$region Render utils}
    
    private function PrevValidItemInd(ind: integer): integer?;
    begin
      while true do
      begin
        if ind<=0 then
        begin
          Result := nil;
          exit;
        end;
        ind := ind-1;
        
        if should_render_item(items[ind].el) then
        begin
          Result := ind;
          exit;
        end;
        
      end;
    end;
    
    private function NextValidItemInd(ind: integer): integer?;
    begin
      while true do
      begin
        ind := ind+1;
        if ind>=items.Count then
        begin
          Result := nil;
          exit;
        end;
        
        if should_render_item(items[ind].el) then
        begin
          Result := ind;
          exit;
        end;
        
      end;
    end;
    
    private procedure ValidatePinn;
    begin
      if (pinned_item_ind <> nil) and should_render_item(items[pinned_item_ind.Value].el) then exit;
      last_item_pinned := false;
//      Writeln('Resetting pinn');
      pinned_item_ind := displayed_items.Cast&<integer?>.FirstOrDefault(ind->should_render_item(items[ind.Value].el));
      if pinned_item_ind <> nil then exit;
      pinned_item_ind := NextValidItemInd(-1);
    end;
    
    {$endregion Render utils}
    
    {$region Render}
    protected top_tint_h, bottom_tint_h: real;
    
    protected function MeasureOverride(availableSize: Size): Size; override;
    begin
      Result := new Size(0, 0);
      
      ValidatePinn;
      if pinned_item_ind = nil then
      begin
        foreach var ind in displayed_items do
        begin
          var item := items[ind];
          self.RemoveVisualChild(item);
          item.UnDisplay;
        end;
        displayed_items.Clear;
        exit;
      end;
      
      var tint_h := MaxTintSize * availableSize.Height;
      
      var prev_items := displayed_items.ToArray;
      displayed_items.Clear;
      
      displayed_items += pinned_item_ind.Value;
      var pinned_item := items[pinned_item_ind.Value];
      pinned_item.Measure(new Size(availableSize.Width, real.PositiveInfinity));
      if real.IsNaN(pinned_item.logical_y) then
      begin
        pinned_item.next_logical_y := 0;
        pinned_item.StartAnimatingY(0);
      end else
        pinned_item.next_logical_y := pinned_item.logical_y + new_scroll;
      new_scroll := 0;
      Result := pinned_item.DesiredSize;
      
      var lower_logical_bound := pinned_item.next_logical_y;
      var lower_visual_bound  := pinned_item.VisualY;
      
      var upper_logical_bound := lower_logical_bound + pinned_item.DesiredSize.Height;
      var upper_visual_bound  := lower_visual_bound  + pinned_item.DesiredSize.Height;
      
      var need_change_pinned := (lower_logical_bound < -0.01) or (upper_logical_bound > availableSize.Height+0.01);
      
      {$region lower}
      
      begin
        var ind := pinned_item_ind;
        
        while true do
        begin
          var logically_disabled := lower_logical_bound < 0;
          var  visually_disabled := lower_visual_bound < -tint_h;
          if logically_disabled and visually_disabled then break;
          
          ind := PrevValidItemInd(ind.Value);
          if ind=nil then break;
          var item := items[ind.Value];
          
          item.Measure(new Size(availableSize.Width, real.PositiveInfinity));
          lower_logical_bound -= item.DesiredSize.Height;
          if real.IsNaN(item.logical_y) then
          begin
            item.logical_y := lower_logical_bound;
            item.StartAnimatingY(lower_visual_bound - item.DesiredSize.Height);
          end;
          item.next_logical_y := lower_logical_bound;
          lower_visual_bound := item.VisualY;
          
          displayed_items += ind.Value;
          Result.Height += item.DesiredSize.Height;
          if logically_disabled or visually_disabled then continue;
          
          Result.Width := Max( Result.Width, item.DesiredSize.Width );
        end;
        
        self.top_tint_h := (-lower_visual_bound).Clamp(0, tint_h);
      end;
      displayed_items.Reverse; // Чтоб элементы списка были в правильном порядке
      
      {$endregion lower}
      
      {$region upper}
      
      begin
        var ind := pinned_item_ind;
        
        while true do
        begin
          var logically_disabled := upper_logical_bound >= availableSize.Height;
          var  visually_disabled := upper_visual_bound  >= availableSize.Height+tint_h;
          if logically_disabled and visually_disabled then break;
          
          ind := NextValidItemInd(ind.Value);
          if ind=nil then break;
          var item := items[ind.Value];
          
          if real.IsNaN(item.logical_y) then
          begin
            item.logical_y := upper_logical_bound;
            item.StartAnimatingY(upper_visual_bound);
          end;
          item.next_logical_y := upper_logical_bound;
          item.Measure(new Size(availableSize.Width, real.PositiveInfinity));
          upper_logical_bound += item.DesiredSize.Height;
          upper_visual_bound := item.VisualY + item.DesiredSize.Height;
          
          displayed_items += ind.Value;
          Result.Height += item.DesiredSize.Height;
          if logically_disabled or visually_disabled then continue;
          
          Result.Width := Max( Result.Width, item.DesiredSize.Width );
        end;
        
        self.bottom_tint_h := (upper_visual_bound-availableSize.Height).Clamp(0, tint_h);
      end;
      
      {$endregion upper}
      
      if lower_logical_bound > 0.01 then
      begin
        pinned_item_ind := displayed_items.First;
        last_item_pinned := false;
        foreach var ind in displayed_items do
          items[ind].next_logical_y -= lower_logical_bound;
        lower_logical_bound := 0;
//        Writeln('Set to low');
      end else
      if upper_logical_bound < availableSize.Height-0.01 then
      begin
        pinned_item_ind := displayed_items.Last;
        last_item_pinned := true;
        var shift := Min( -lower_logical_bound, availableSize.Height - upper_logical_bound );
        foreach var ind in displayed_items do
          items[ind].next_logical_y += shift;
        lower_logical_bound += shift;
        upper_logical_bound += shift;
//        Writeln('Set to high');
      end else
      if need_change_pinned then
      begin
        pinned_item_ind := displayed_items[(displayed_items.Count-1) div 2];
        last_item_pinned := false;
//        Writeln('Set to middle');
      end;
      
      foreach var ind in displayed_items do
        items[ind].ComfirmRealY;
      
      Result.Height := Result.Height.ClampTop(availableSize.Height);
//      if Result <> self.DesiredSize then UIElement(Parent).InvalidateMeasure;
      
      foreach var ind in prev_items.Except(displayed_items) do
      begin
        var item := items[ind];
        self.RemoveVisualChild(item);
        item.UnDisplay;
      end;
      
      foreach var ind in displayed_items.Except(prev_items) do
      begin
        var item := items[ind];
        self.AddVisualChild(item);
      end;
      
//      top_tint_h.Println;
//      bottom_tint_h.Println;
//      lower_visual_bound.Println;
//      upper_visual_bound.Println;
//      Writeln('='*30);
      
//      SeqWhile(self as FrameworkElement, el->el.Parent as FrameworkElement, el->el<>nil)
//      .PrintLines(el->el.GetType);
//      Writeln(availableSize.Width);
//      Writeln(Result.Width);
//      foreach var ind in displayed_items do
//      begin
//        var item := items[ind];
//        Writeln(item.el);
//        Writeln(item.DesiredSize.Width);
//      end;
//      Writeln('='*30);
      
//      if _ObjectToString(pinned_item.el.GetVisualChild(0)?.GetVisualChild(0)?.GetType).Contains('LayerTestsContainer') then
//      begin
//        Writeln('DisplayList:');
//        Writeln(availableSize);
//        Writeln(Result);
//        Writeln(pinned_item.el.GetType);
//        Writeln(pinned_item.el.DesiredSize);
//        Writeln((pinned_item.el as SmoothResizer).SmoothX);
//        Writeln(displayed_items.Count);
//        
//        var p := Parent as FrameworkElement;
//        while p<>nil do
//        begin
//          Writeln(p.GetType);
//          p := p.Parent as FrameworkElement;
//        end;
//        
////        Writeln(pinned_item.el.GetType);
////        Writeln(pinned_item.el.GetVisualChild(0)?.GetType);
////        Writeln(pinned_item.el.GetVisualChild(0)?.GetVisualChild(0)?.GetType);
//        Writeln('='*30);
//      end;
      
      UIElement(Parent).InvalidateArrange;
    end;
    
    protected function ArrangeOverride(finalSize: Size): Size; override;
    begin
      Result := new Size(finalSize.Width, 0);
      if displayed_items.Count=0 then exit;
      
      foreach var ind in displayed_items do
      begin
        var item := items[ind];
        item.Arrange(new Rect(0, item.VisualY, finalSize.Width, item.DesiredSize.Height));
        
        Result.Width := Max( Result.Width, item.DesiredSize.Width );
        Result.Height += item.DesiredSize.Height;
        
      end;
      
      var first_item := items[displayed_items.First];
      if Max(first_item.VisualY, first_item.logical_y) + first_item.DesiredSize.Height < 0 then
        self.InvalidateMeasure else
      begin
        var last_item := items[displayed_items.Last];
        if Min(last_item.VisualY, last_item.logical_y) > finalSize.Height then
          self.InvalidateMeasure;
      end;
      
    end;
    
    {$endregion Render}
    
  end;
  
  DisplayList<T> = class(FrameworkElement)
  where T: FrameworkElement;
    
    {$region Changable}
    
    protected function ShouldRenderItem(item: T): boolean; virtual := true;
    
    protected procedure HandleHeaderClick(e: System.Windows.Input.MouseButtonEventArgs); virtual :=
    self.ShowItems := not ShowItems;
    
    {$endregion Changable}
    
    private show_items := true;
    public property ShowItems: boolean read show_items write
    begin
      if show_items=value then exit;
      show_items := value;
      self.InvalidateMeasure;
    end;
    
    {$region Main elements}
    
    {$region Header}
    
    private _header: FrameworkElement;
    private header_wrap := new ClickableContent;
    public property Header: FrameworkElement read _header write
    begin
      _header := value;
      header_wrap.Content := value;
    end;
    
    {$endregion Header}
    
    {$region Contents}
    
    private contents := new __DisplayListContents<T>(ShouldRenderItem);
    private contents_visualy_added := false;
    
    public procedure AddElement(el: T) := AddElement(el, el);
    public procedure AddElement(el: T; anchor: FrameworkElement) :=
    contents.AddItem(new __DisplayListItem<T>(el, anchor));
    
    private items_shift := 0.0;
    public property ItemsShift: real read items_shift write
    begin
      if items_shift = value then exit;
      items_shift := value;
      if ShowItems then
        self.InvalidateMeasure;
    end;
    
    public property MaxItemsHeight: real read contents.MaxHeight write contents.MaxHeight := value;
    
    {$endregion Contents}
    
    {$region Item lines}
    
    private item_lines := new Line[0];
    private function MakeNewLine: Line;
    begin
      Result := new Line;
      Result.Stroke := new SolidColorBrush(Colors.Black);
      Result.StrokeThickness := 1;
    end;
    
    {$endregion Item lines}
    
    {$region Tint rects}
    
    private function InitTintRects: array of Rectangle;
    begin
      Result := new Rectangle[2];
      
      Result[0] := new Rectangle;
      Result[0].Fill := new LinearGradientBrush(Colors.White, Colors.Transparent, 90);
      
      Result[1] := new Rectangle;
      Result[1].Fill := new LinearGradientBrush(Colors.Transparent, Colors.White, 90);
      
    end;
    private tint_rects := InitTintRects;
    
    {$endregion Tint rects}
    
    {$region Vertical line}
    
    private vertical_line := MakeNewLine;
    
    {$endregion Vertical line}
    
    {$endregion Main elements}
    
//    private static last_dl_ind := 0;
//    private curr_dl_ind: integer;
    public constructor;
    begin
//      last_dl_ind += 1;
//      curr_dl_ind := last_dl_ind;
      
      self.AddLogicalChild(header_wrap);
      self.AddVisualChild(header_wrap);
      header_wrap.Click += (o,e)->self.HandleHeaderClick(e);
      
      self.AddLogicalChild(vertical_line);
      
      self.AddLogicalChild(contents);
      
      InitTintRects;
      foreach var tint_rect in tint_rects do
        self.AddLogicalChild(tint_rect);
      
    end;
    
    {$region Visual children}
    
    // contents + item_lines + tint_rects + vertical_line + header
    protected property VisualChildrenCount: integer read ShowItems ? 1+item_lines.Count+tint_rects.Length+1+1 : 1; override;
    protected function GetVisualChild(ind: integer): Visual; override;
    begin
      if ind < 0 then raise new System.ArgumentOutOfRangeException('ind');
      
      if ShowItems then
      begin
        
        if ind < 1 then
        begin
          Result := contents;
          exit;
        end;
        ind -= 1;
        
        if ind < item_lines.Length then
        begin
          Result := item_lines[ind];
          exit;
        end;
        ind -= item_lines.Length;
        
        if ind < 2 then
        begin
          Result := tint_rects[ind];
          exit;
        end;
        ind -= 2;
        
        if ind < 1 then
        begin
          Result := vertical_line;
          exit;
        end;
        ind -= 1;
        
      end;
      
      if ind < 1 then
      begin
        Result := header_wrap;
        exit;
      end;
      ind -= 1;
      
      raise new System.ArgumentOutOfRangeException('ind');
    end;
    
    {$endregion Visual children}
    
    {$region Render}
    
    protected function MeasureOverride(availableSize: Size): Size; override;
    begin
//      if Header<>nil then Header.InvalidateMeasure;
      header_wrap.Measure(availableSize);
      Result := header_wrap.DesiredSize;
      
//      if not ShowItems then
//      begin
//        Writeln(availableSize.Width);
//        Writeln(header_wrap.DesiredSize.Width);
//        Writeln('='*30);
//      end;
      
      if ShowItems then
      begin
        contents.InvalidateMeasure;
        contents.Measure(new Size(
          (availableSize.Width-ItemsShift).ClampBottom(0),
          (availableSize.Height-Result.Height).ClampBottom(0)
        ));
        Result.Width := Max( Result.Width, contents.DesiredSize.Width+ItemsShift );
        Result.Height += contents.DesiredSize.Height;
      end;
      
//      Writeln(contents.
//      Writeln(Result);
//      if self.GetType.ToString.Contains('LayerTestsContainer') then
//      begin
//        Writeln(availableSize);
//        Writeln(Result);
//        Writeln('='*30);
//      end;
    end;
    
    protected function ArrangeOverride(finalSize: Size): Size; override;
    begin
      header_wrap.Arrange(new Rect(0,0, finalSize.Width,header_wrap.DesiredSize.Height));
      Result.Width := finalSize.Width;
      var header_height := header_wrap.DesiredSize.Height;
      Result.Height := header_height;
      
      if contents_visualy_added <> ShowItems then
      begin
        
        if ShowItems then
        begin
          self.AddVisualChild(contents);
          foreach var line in item_lines do
            self.AddVisualChild(line);
          foreach var tint_rect in tint_rects do
            self.AddVisualChild(tint_rect);
          self.AddVisualChild(vertical_line);
        end else
        begin
          self.RemoveVisualChild(contents);
          foreach var line in item_lines do
            self.RemoveVisualChild(line);
          foreach var tint_rect in tint_rects do
            self.RemoveVisualChild(tint_rect);
          self.RemoveVisualChild(vertical_line);
        end;
        
        contents_visualy_added := ShowItems;
      end;
      
      if ShowItems then
      begin
        
//        contents.InvalidateArrange;
        contents.Arrange(new Rect(ItemsShift, Result.Height,
          (finalSize.Width-ItemsShift).ClampBottom(0),
          contents.DesiredSize.Height
        ));
        Result.Height += contents.DesiredSize.Height;
        
        tint_rects[0].Arrange(new Rect(0,header_height, finalSize.Width,contents.top_tint_h));
        tint_rects[1].Arrange(new Rect(0,finalSize.Height-contents.bottom_tint_h, finalSize.Width,contents.bottom_tint_h));
        
        var max_y := 0.0;
        // item_lines
        begin
          var new_item_lines := new List<Line>;
          var prev_item_lines_ind := 0;
          
          foreach var ind in contents.displayed_items do
          begin
            var item: __DisplayListItem<T> := contents.items[ind];
            var y := item.anchor.TranslatePoint(new Point(0, item.anchor.ActualHeight/2), contents).Y;
            if y < 0 then continue;
//            if y > contents.DesiredSize.Height then continue;
            if y > max_y then max_y := y;
            
            var l: Line;
            if prev_item_lines_ind = item_lines.Length then
              l := MakeNewLine else
            begin
              l := item_lines[prev_item_lines_ind];
              prev_item_lines_ind += 1;
            end;
            new_item_lines += l;
            
            l.X1 := ItemsShift/2;
            l.X2 := ItemsShift;
            
            l.Y1 := y;
            l.Y2 := y;
            
            l.Arrange(new Rect(0, header_height, finalSize.Width, contents.DesiredSize.Height));
          end;
          
          foreach var line in item_lines.Except(new_item_lines) do
            self.RemoveVisualChild(line);
          
          foreach var line in new_item_lines.Except(item_lines) do
            self.AddVisualChild(line);
          
          self.item_lines := new_item_lines.ToArray;
        end;
        
        vertical_line.X1 := ItemsShift/2;
        vertical_line.X2 := ItemsShift/2;
        vertical_line.Y1 := 0;
        vertical_line.Y2 := max_y;
        vertical_line.Arrange(new Rect(0, header_height, finalSize.Width, contents.DesiredSize.Height));
        
      end;
      
    end;
    
    {$endregion Render}
    
  end;
  
  SimpleDisplayList = DisplayList<FrameworkElement>;
  
end.