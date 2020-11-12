unit DisplayListData;

uses System.Windows;
uses System.Windows.Controls;
uses System.Windows.Media;

uses VUtils;

type
  
  DisplayListElement = sealed class
    public item, item_anchor: FrameworkElement;
    public measured_size: Size;
    public line := new System.Windows.Shapes.Line;
    
    public constructor(item, item_anchor: FrameworkElement);
    begin
      self.item         := item;
      self.item_anchor  := item_anchor;
      
      line.Stroke := new SolidColorBrush(Colors.Black);
      line.StrokeThickness := 1;
      
    end;
    
  end;
  
  DisplayListContents = sealed class
    private AddChild, RemoveChild: FrameworkElement->();
    private l := new List<DisplayListElement>;
    
    public constructor(AddChild, RemoveChild: FrameworkElement->());
    begin
      self.AddChild     := AddChild;
      self.RemoveChild  := RemoveChild;
    end;
    private constructor := raise new System.InvalidOperationException;
    
    public procedure Add(item, item_anchor: FrameworkElement);
    begin
      var el := new DisplayListElement(item, item_anchor);
      AddChild(item);
      AddChild(el.line);
      l.Add(el);
    end;
    public procedure Add(item: FrameworkElement) := self.Add(item, item);
    
    public function Remove(item: FrameworkElement): boolean;
    begin
      Result := false;
      
      for var i := 0 to l.Count-1 do
        if l[i].item = item then
        begin
          var el := l[i];
          RemoveChild(item);
          RemoveChild(el.line);
          l.RemoveAt(i);
          Result := true;
          exit;
        end;
      
    end;
    
    public property Count: integer read l.Count;
    public property Item[i: integer]: FrameworkElement read l[i].item; default;
    
  end;
  
  DisplayList = class(FrameworkElement)
    
    private _header: FrameworkElement;
    private header_wrap := new ClickableContent;
    public property Header: FrameworkElement read _header write
    begin
      _header := value;
      header_wrap.Content := value;
    end;
    private header_line := new System.Windows.Shapes.Line;
    
    private procedure ChildAdded(add_item: FrameworkElement);
    begin
      self.AddLogicalChild(add_item);
      if ShowChildren then
      begin
        self.InvalidateMeasure;
        self.AddVisualChild(add_item);
      end;
    end;
    private procedure ChildRemoved(rem_item: FrameworkElement);
    begin
      self.RemoveLogicalChild(rem_item);
      if ShowChildren then
      begin
        self.InvalidateMeasure;
        self.RemoveVisualChild(rem_item);
      end;
    end;
    private _children := new DisplayListContents(ChildAdded, ChildRemoved);
    public property Children: DisplayListContents read _children;
    
    private show_children := true;
    public property ShowChildren: boolean read show_children write
    begin
      if show_children=value then exit;
      show_children := value;
      self.InvalidateMeasure;
    end;
    
    private children_shift := 0.0;
    public property ChildrenShift: real read children_shift write
    begin
      children_shift := value;
      if ShowChildren then
        self.InvalidateMeasure;
    end;
    
    public constructor;
    begin
      
      self.AddLogicalChild(header_wrap);
      self.AddVisualChild(header_wrap);
      header_wrap.Click += (o,e)->
      begin
        ShowChildren := not ShowChildren;
      end;
      
      self.AddLogicalChild(header_line);
      self.AddVisualChild(header_line);
      header_line.Stroke := new SolidColorBrush(Colors.Black);
      header_line.StrokeThickness := 1;
      
    end;
    
    protected property VisualChildrenCount: integer read
      integer(Header<>nil) +
      integer((Header<>nil) and show_children and (Children.Count<>0)) +
      integer(show_children and (Children.Count<>0)) * Children.Count * 2; override;
    protected function GetVisualChild(ind: integer): Visual; override;
    begin
      if ind<0 then raise new System.ArgumentOutOfRangeException('ind');
      
      if Header<>nil then
      begin
        
        if ind=0 then
        begin
          Result := header_wrap;
          exit;
        end;
        
        ind -= 1;
      end;
      
      var ch_shown := show_children and (Children.Count<>0);
      if (Header<>nil) and ch_shown then
      begin
        
        if ind=0 then
        begin
          Result := header_line;
          exit;
        end;
        
        ind -= 1;
      end;
      
      if ch_shown then
      begin
        
        if ind < Children.Count then
        begin
          Result := Children[ind];
          exit;
        end;
        ind -= Children.Count;
        
        if ind < Children.Count then
        begin
          Result := Children.l[ind].line;
          exit;
        end;
        ind -= Children.Count;
        
      end;
      
      raise new System.ArgumentOutOfRangeException('ind');
    end;
    
    private children_visually_added := ShowChildren;
    protected function MeasureOverride(availableSize: Size): Size; override;
    begin
      
      if Header=nil then
        Result := new Size(0,0) else
      begin
        header_wrap.Measure(availableSize);
        Result := header_wrap.DesiredSize;
      end;
      
      if show_children <> children_visually_added then
      begin
        
        if show_children then
        begin
          self.AddVisualChild(header_line);
          foreach var el in Children.l do
          begin
            self.AddVisualChild(el.item);
            self.AddVisualChild(el.line);
          end;
        end else
        begin
          self.RemoveVisualChild(header_line);
          foreach var el in Children.l do
          begin
            self.RemoveVisualChild(el.item);
            self.RemoveVisualChild(el.line);
          end;
        end;
        
        children_visually_added := show_children;
      end;
      
      if not show_children then exit;
      if Children.Count=0 then exit;
      
      var max_child_w := ( availableSize.Width-self.ChildrenShift ).ClampBottom(0);
      foreach var el in Children.l do
      begin
        var max_child_h := ( availableSize.Height-Result.Height ).ClampBottom(0);
        
        el.item.Measure(new Size(max_child_w, max_child_h));
        var sz := el.item.DesiredSize;
        sz.Width  := sz.Width .ClampTop(max_child_w);
        sz.Height := sz.Height.ClampTop(max_child_h);
        el.measured_size := sz;
        
        Result.Width := Max(Result.Width, sz.Width+self.ChildrenShift);
        Result.Height += sz.Height;
      end;
      
    end;
    
    protected function ArrangeOverride(finalSize: Size): Size; override;
    begin
      
      if Header=nil then
        Result := new Size(0, 0) else
      begin
        Result := new Size(finalSize.Width, header_wrap.DesiredSize.Height);
        header_wrap.Arrange(new Rect(Result));
      end;
      
      if not show_children then exit;
      if Children.Count=0 then exit;
      
      var max_child_w := ( finalSize.Width-self.ChildrenShift ).ClampBottom(0);
      var last_y := 0.0;
      foreach var el in Children.l do
      begin
        var sz := el.measured_size;
        
        el.item.Arrange(new Rect(self.ChildrenShift, Result.Height, max_child_w, sz.Height));
        el.line.Arrange(new Rect(finalSize));
        
        Result.Width := Max(Result.Width, sz.Width+self.ChildrenShift);
        Result.Height += sz.Height;
        
        var anchor_p := el.item_anchor.TranslatePoint(new Point(0, el.item_anchor.ActualHeight/2), self);
//        var anchor_p := self.PointFromScreen(el.item_anchor.PointToScreen(new Point(0, el.item_anchor.ActualHeight/2)));
        var last_x := anchor_p.X;
        last_y := anchor_p.Y;
        
        var l := el.line;
        l.X1 := ChildrenShift/2;
        l.X2 := last_x;
        l.Y1 := last_y;
        l.Y2 := last_y;
        
      end;
      
      header_line.X1 := ChildrenShift/2;
      header_line.X2 := ChildrenShift/2;
      header_line.Y1 := header_wrap.DesiredSize.Height;
      header_line.Y2 := last_y;
      header_line.Arrange(new Rect(finalSize));
      
    end;
    
  end;
  
end.