unit VUtils;

{$reference PresentationFramework.dll}
{$reference PresentationCore.dll}
{$reference WindowsBase.dll}

uses System;
uses System.Windows;
uses System.Windows.Media.Animation;
uses System.Windows.Controls;

type
  
  CachedImageSource = sealed class
    private static all := new Dictionary<string, CachedImageSource>;
    private fr: System.Windows.Media.Imaging.BitmapFrame;
    private waiting_imgs := new List<Image>;
    
    public constructor(res_name: string);
    begin
      System.Threading.Thread.Create(()->
      try
        self.fr := System.Windows.Media.Imaging.BitmapFrame.Create(
          GetResourceStream(res_name),
          System.Windows.Media.Imaging.BitmapCreateOptions.IgnoreImageCache,
          System.Windows.Media.Imaging.BitmapCacheOption.None
        );
        lock self do
        begin
          foreach var img in waiting_imgs do
            img.Dispatcher.InvokeAsync(()->
            try
              img.Source := self.fr;
            except
              on e: Exception do
                MessageBox.Show(e.ToString);
            end);
          waiting_imgs := nil;
        end;
      except
        on e: Exception do
          MessageBox.Show(e.ToString);
      end).Start;
      all[res_name] := self;
    end;
    private constructor := raise new System.InvalidOperationException;
    
    public procedure Apply(img: Image);
    begin
      if waiting_imgs=nil then
        img.Source := fr else
      lock self do
        if waiting_imgs=nil then
          img.Source := self.fr else
          waiting_imgs += img;
    end;
    
    private static function GetFromResName(res_name: string): CachedImageSource;
    begin
      lock all do
        if not all.TryGetValue(res_name, Result) then
          Result := new CachedImageSource(res_name);
    end;
    public static property FromResName[res_name: string]: CachedImageSource read GetFromResName; default;
    
  end;
  
  ClickableContent = class(ContentControl)
    private clicked_inside := false;
    
    public event Click: System.Windows.Input.MouseButtonEventHandler;
    
    public constructor;
    begin
      self.MouseDown  += (o,e)->begin clicked_inside := true  end;
      self.MouseLeave += (o,e)->begin clicked_inside := false end;
      self.MouseUp += (o,e)->
      if clicked_inside then
      begin
        var Click := self.Click;
        if Click<>nil then Click(o,e);
        clicked_inside := false;
      end;
    end;
    
  end;
  
  StackedHeap = class(Grid)
    
    protected function MeasureOverride(availableSize: Size): Size; override;
    begin
      Result := default(Size);
      foreach var item: UIElement in self.Children do
      begin
        item.Measure(availableSize);
        Result. Width := Result. Width.ClampBottom(item.DesiredSize. Width);
        Result.Height := Result.Height.ClampBottom(item.DesiredSize.Height);
      end;
      
//      Writeln(Result);
//      Writeln(self.GetType);
//      Writeln(self.Parent.GetType);
//      foreach var item: UIElement in self.Children do
//      begin
//        Writeln(item.GetType);
//        Writeln(item.DesiredSize);
//      end;
//      Writeln('='*30);
      
    end;
    
    protected function ArrangeOverride(finalSize: Size): Size; override;
    begin
      foreach var item: UIElement in self.Children do
        item.Arrange(new Rect(finalSize));
      Result := finalSize;
    end;
    
  end;
  
  SmoothDoubleAnimation = sealed class(DoubleAnimationBase)
    private const default_eps = 0.1;
    private const default_k = 0.35;
    private const tick_scale = 1000000;
    
    private curr_val: real;
    private target: ()->real;
    private eps: real;
    private k: real;
    public constructor(start_val: real; target: ()->real; eps: real := default_eps; k: real := default_k);
    begin
      self.curr_val := start_val;
      self.target   := target;
      self.Duration := System.Windows.Duration.Forever;
      self.eps      := eps;
      self.k        := k;
    end;
    private constructor := raise new System.InvalidOperationException;
    
    private last_t: System.TimeSpan;
    
    public function GetCurrentValueCore(defaultOriginValue, defaultDestinationValue: real; ac: AnimationClock): real; override;
    begin
      var target := self.target();
      
      var l := target-curr_val;
      if Abs(l) < eps then
        curr_val := target else
        curr_val += l * (1 - k) ** (tick_scale/(ac.CurrentTime.Value - last_t).Ticks);
      
      last_t := ac.CurrentTime.Value;
      Result := curr_val;
    end;
    
    protected function CreateInstanceCore: Freezable; override :=
    new SmoothDoubleAnimation(curr_val, target, eps, k);
    
  end;
  
  SmoothProgressBar = class(ProgressBar)
    
    private max_animated := false;
    public procedure SnapMax(max: real);
    begin
      self.BeginAnimation(ProgressBar.MaximumProperty, nil);
      max_animated := false;
      self.Maximum := max;
    end;
    private target_max: real;
    public procedure AnimateMax(max: real);
    begin
      self.target_max := max;
      if not max_animated then
      begin
        self.BeginAnimation(ProgressBar.MaximumProperty, new SmoothDoubleAnimation(self.Maximum, ()->self.target_max, 0));
        max_animated := true;
      end;
    end;
    
    private val_animated := false;
    public procedure SnapVal(val: real);
    begin
      self.BeginAnimation(ProgressBar.ValueProperty, nil);
      val_animated := false;
      self.Value := val;
    end;
    private target_val: real;
    public procedure AnimateVal(val: real);
    begin
      self.target_val := val;
      if not val_animated then
      begin
        self.BeginAnimation(ProgressBar.ValueProperty, new SmoothDoubleAnimation(self.Value, ()->self.target_val, 0));
        val_animated := true;
      end;
    end;
    
    protected function MeasureOverride(availableSize: Size): Size; override := new Size(2,2);
    
  end;
  
  SmoothResizer = class(ContentControl)
    private ExtentX, ExtentY: real;
    
    public constructor :=
    self.ClipToBounds := true;
    
    {$region AnimLimit}
    
    private static AnimXLimitProp := DependencyProperty.Register(
      'AnimXLimit', typeof(real), typeof(SmoothResizer),
      new FrameworkPropertyMetadata(
        0.0, FrameworkPropertyMetadataOptions.AffectsMeasure
      )
    );
    public property AnimXLimit: real read real(GetValue(AnimXLimitProp)) write SetValue(AnimXLimitProp, value);
    
    private static AnimYLimitProp := DependencyProperty.Register(
      'AnimYLimit', typeof(real), typeof(SmoothResizer),
      new FrameworkPropertyMetadata(
        0.0, FrameworkPropertyMetadataOptions.AffectsMeasure
      )
    );
    public property AnimYLimit: real read real(GetValue(AnimYLimitProp)) write SetValue(AnimYLimitProp, value);
    
    {$endregion AnimLimit}
    
    {$region Snap}
    
    private snap_x := false;
    public procedure SnapX;
    begin
      Dispatcher.VerifyAccess;
      snap_x := true;
      self.InvalidateMeasure;
    end;
    
    private snap_y := false;
    public procedure SnapY;
    begin
      Dispatcher.VerifyAccess;
      snap_y := true;
      self.InvalidateMeasure;
    end;
    
    {$endregion Snap}
    
    {$region Smooth}
    
    private _SmoothX := false;
    public property SmoothX: boolean read _SmoothX write
    begin
      if _SmoothX=value then exit;
      _SmoothX := value;
      self.InvalidateMeasure;
    end;
    
    private _SmoothY := false;
    public property SmoothY: boolean read _SmoothY write
    begin
      if _SmoothY=value then exit;
      _SmoothY := value;
      self.InvalidateMeasure;
    end;
    
    {$endregion Smooth}
    
    {$region Fill}
    
    private _FillX := true;
    public property FillX: boolean read _FillX write
    begin
      if FillX=value then exit;
      _FillX := value;
      self.InvalidateMeasure;
    end;
    
    private _FillY := true;
    public property FillY: boolean read _FillY write
    begin
      if FillY=value then exit;
      _FillY := value;
      self.InvalidateMeasure;
    end;
    
    {$endregion Fill}
    
    {$region Alignment}
    
    private _HorizontalAlignment := System.Windows.HorizontalAlignment.Stretch;
    public property HorizontalAlignment: System.Windows.HorizontalAlignment read _HorizontalAlignment write
    begin
      if _HorizontalAlignment=value then exit;
      _HorizontalAlignment := value;
      self.InvalidateMeasure;
    end;
    
    private _VerticalAlignment := System.Windows.VerticalAlignment.Stretch;
    public property VerticalAlignment: System.Windows.VerticalAlignment read _VerticalAlignment write
    begin
      if _VerticalAlignment=value then exit;
      _VerticalAlignment := value;
      self.InvalidateMeasure;
    end;
    
    {$endregion Alignment}
    
    protected procedure OnContentChanged(oldContent, newConten: object); override;
    begin
      inherited; // Сама замена .Content происходит тут
      
      if (oldContent=nil) <> (newConten=nil) then
        if newConten=nil then
        begin
          if SmoothX then self.BeginAnimation(SmoothResizer.AnimXLimitProp, nil);
          if SmoothY then self.BeginAnimation(SmoothResizer.AnimYLimitProp, nil);
        end else
        begin
          if SmoothX then self.BeginAnimation(SmoothResizer.AnimXLimitProp, new SmoothDoubleAnimation(AnimXLimit, ()->self.ExtentX));
          if SmoothY then self.BeginAnimation(SmoothResizer.AnimYLimitProp, new SmoothDoubleAnimation(AnimYLimit, ()->self.ExtentY));
        end;
      
      self.InvalidateMeasure;
    end;
    
    protected function MeasureOverride(availableSize: Size): Size; override;
    begin
      Result := default(Size);
      
      if VisualChildrenCount=0 then exit;
      var child := GetVisualChild(0) as UIElement;
      if child=nil then raise new System.InvalidOperationException;
      
      child.Measure(availableSize);
      ExtentX := if FillX then
      (
        if not real.IsInfinity(availableSize.Width) then
          Max(child.DesiredSize.Width, availableSize.Width) else
          child.DesiredSize.Width
      ) else
        child.DesiredSize.Width;
      ExtentY := if FillY then
      (
        if not real.IsInfinity(availableSize.Height) then
          Max(child.DesiredSize.Height, availableSize.Height) else
          child.DesiredSize.Height
      ) else
        child.DesiredSize.Height;
      
//      SeqWhile(self as FrameworkElement, el->el.Parent as FrameworkElement, el->el<>nil)
//      .PrintLines(el->el.GetType);
//      Writeln(availableSize.Width);
//      Writeln(child.DesiredSize.Width);
//      Writeln(ExtentX);
//      Writeln('='*30);
      
//      if Parent.GetType.ToString.Contains('MinimizationLog') then
//        Writeln(child.DesiredSize);
      
      if snap_x then
      begin
        if not SmoothX then raise new System.InvalidOperationException;
        self.BeginAnimation(SmoothResizer.AnimXLimitProp, new SmoothDoubleAnimation(ExtentX, ()->self.ExtentX));
        snap_x := false;
      end;
      
      if snap_y then
      begin
        if not SmoothY then raise new System.InvalidOperationException;
        self.BeginAnimation(SmoothResizer.AnimYLimitProp, new SmoothDoubleAnimation(ExtentY, ()->self.ExtentY));
        snap_y := false;
      end;
      
//      Result := new Size(
//        if SmoothX then AnimXLimit else ExtentX,
//        if SmoothY then AnimYLimit else ExtentY
//      );
      Result := new Size(
        if SmoothX then AnimXLimit else child.DesiredSize.Width,
        if SmoothY then AnimYLimit else child.DesiredSize.Height
      );
      
      // SmoothResizer shouldn't re-measure child, because measure only determines min size
//      child.Measure(Result);
      
    end;
    
    protected function ArrangeOverride(finalSize: Size): Size; override;
    begin
      Result := default(Size);
      
      // Proper check is in MeasureOverride
      var child := GetVisualChild(0) as UIElement;
      if child=nil then exit;
      
      Result.Width :=
        if self.HorizontalAlignment <> System.Windows.HorizontalAlignment.Stretch then child.DesiredSize.Width else
        if FillX then finalSize.Width.ClampBottom(child.DesiredSize.Width) else
        if SmoothX then AnimXLimit else
          child.DesiredSize.Width;
      
      Result.Height :=
        if self.VerticalAlignment <> System.Windows.VerticalAlignment.Stretch then child.DesiredSize.Height else
        if FillY then finalSize.Height.ClampBottom(child.DesiredSize.Height) else
        if SmoothY then AnimYLimit else
          child.DesiredSize.Height;
      
      var origin: Point;
      case self.HorizontalAlignment of
        System.Windows.HorizontalAlignment.Left: origin.X := 0;
        System.Windows.HorizontalAlignment.Stretch,
        System.Windows.HorizontalAlignment.Center: origin.X := (finalSize.Width-Result.Width).ClampBottom(0)/2;
        System.Windows.HorizontalAlignment.Right:  origin.X := (finalSize.Width-Result.Width).ClampBottom(0);
        else raise new System.InvalidOperationException(self.HorizontalAlignment.ToString);
      end;
      case self.VerticalAlignment of
        System.Windows.VerticalAlignment.Top: origin.Y := 0;
        System.Windows.VerticalAlignment.Stretch,
        System.Windows.VerticalAlignment.Center: origin.Y := (finalSize.Height-Result.Height).ClampBottom(0)/2;
        System.Windows.VerticalAlignment.Bottom: origin.Y := (finalSize.Height-Result.Height).ClampBottom(0);
        else raise new System.InvalidOperationException(self.VerticalAlignment.ToString);
      end;
      
//      Writeln(new Rect(origin, Result));
      child.Arrange(new Rect(origin, Result));
      Result := finalSize;
    end;
    
  end;
  
end.