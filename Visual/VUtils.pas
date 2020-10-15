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
            begin
              img.Source := self.fr;
            end);
          waiting_imgs := nil;
        end;
      except
        on e: Exception do
          Writeln(e.ToString);
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
  
  ClickableTextBlock = class(TextBlock)
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
  
  SmoothDoubleAnimation = sealed class(DoubleAnimationBase)
    private const default_eps = 0.1;
    private const default_k = 0.35;
    private const tick_scale = 1000000;
    private static rest_time := TimeSpan.FromMilliseconds(70);
    
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
      
      if ac.CurrentTime.Value > rest_time then
      begin
        var target := self.target();
        
        var l := target-curr_val;
        if Abs(l) < eps then
          curr_val := target else
          curr_val += l * (1 - k) ** (tick_scale/(ac.CurrentTime.Value - last_t).Ticks);
        
      end;
      
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
    
  end;
  
  SmoothResizer = class(ContentControl)
    public ExtentSize: Size;
    
    private static AnimXLimitProp := DependencyProperty.Register('AnimXLimit', typeof(real), typeof(SmoothResizer), new FrameworkPropertyMetadata(0.0, FrameworkPropertyMetadataOptions.AffectsMeasure));
    private static AnimYLimitProp := DependencyProperty.Register('AnimYLimit', typeof(real), typeof(SmoothResizer), new FrameworkPropertyMetadata(0.0, FrameworkPropertyMetadataOptions.AffectsMeasure));
    
    public property AnimXLimit: real read real(GetValue(AnimXLimitProp)) write SetValue(AnimXLimitProp, value);
    public property AnimYLimit: real read real(GetValue(AnimYLimitProp)) write SetValue(AnimYLimitProp, value);
    
    public SmoothX := true;
    public SmoothY := true;
    
    private snap_x_f, snap_y_f: real->real;
    public procedure SnapX(val_f: real->real);
    begin
      lock self do snap_x_f := val_f;
      self.InvalidateMeasure;
    end;
    public procedure SnapY(val_f: real->real);
    begin
      lock self do snap_y_f := val_f;
      self.InvalidateMeasure;
    end;
    
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
          if SmoothX then self.BeginAnimation(SmoothResizer.AnimXLimitProp, new SmoothDoubleAnimation(AnimXLimit, ()->self.ExtentSize.Width));
          if SmoothY then self.BeginAnimation(SmoothResizer.AnimYLimitProp, new SmoothDoubleAnimation(AnimYLimit, ()->self.ExtentSize.Height));
        end;
      
      self.InvalidateMeasure;
    end;
    
    protected function MeasureOverride(availableSize: Size): Size; override;
    begin
      Result := default(Size);
      
      if VisualChildrenCount=0 then exit;
      var child := GetVisualChild(0) as UIElement;
      if child=nil then exit;
      
      child.Measure(availableSize);
      ExtentSize := new Size(
        Min(child.DesiredSize.Width,  availableSize.Width),
        Min(child.DesiredSize.Height, availableSize.Height)
      );
      
      lock self do
      begin
        
        if snap_x_f<>nil then
        begin
          if not SmoothX then raise new System.InvalidOperationException;
          self.BeginAnimation(SmoothResizer.AnimXLimitProp, new SmoothDoubleAnimation(snap_x_f(ExtentSize.Width ), ()->self.ExtentSize.Width ));
          snap_x_f := nil;
        end;
        
        if snap_y_f<>nil then
        begin
          if not SmoothY then raise new System.InvalidOperationException;
          self.BeginAnimation(SmoothResizer.AnimYLimitProp, new SmoothDoubleAnimation(snap_y_f(ExtentSize.Height), ()->self.ExtentSize.Height));
          snap_y_f := nil;
        end;
        
      end;
      
      Result := new Size(
        SmoothX ? AnimXLimit : child.DesiredSize.Width,
        SmoothY ? AnimYLimit : child.DesiredSize.Height
      );
      
    end;
    
  end;
  
end.