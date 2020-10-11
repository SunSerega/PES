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
  
  SmoothDoubleAnimation = sealed class(DoubleAnimationBase)
    private const k = 0.35;
    private const tick_scale = 1000000;
    private static rest_time := TimeSpan.FromMilliseconds(70);
    
    private curr_val: real;
    private target: ()->real;
    private eps: real;
    private constructor(start_val: real; target: ()->real; eps: real := 0.1);
    begin
      self.curr_val := start_val;
      self.target   := target;
      self.Duration := System.Windows.Duration.Forever;
      self.eps      := eps;
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
    new SmoothDoubleAnimation(curr_val, target, eps);
    
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
  
  SmoothResizer = sealed class(ScrollViewer)
    
    public constructor;
    begin
      self.VerticalScrollBarVisibility := ScrollBarVisibility.Hidden;
      self.HorizontalScrollBarVisibility := ScrollBarVisibility.Hidden;
      self.Visibility := System.Windows.Visibility.Collapsed;
    end;
    
    protected procedure OnMouseWheel(e: System.Windows.Input.MouseWheelEventArgs); override := exit;
    
    protected procedure OnContentChanged(oldContent, newConten: object); override;
    begin
      inherited; // Сама замена .Content происходит тут
      
      if newConten=nil then
      begin
        self.Visibility := System.Windows.Visibility.Collapsed;
        self.BeginAnimation(SmoothResizer.WidthProperty,  nil);
        self.BeginAnimation(SmoothResizer.HeightProperty, nil);
      end else
      begin
        self.Visibility := System.Windows.Visibility.Visible;
        self.BeginAnimation(SmoothResizer.WidthProperty,  new SmoothDoubleAnimation(0, ()->self.ExtentWidth));
//        self.BeginAnimation(SmoothResizer.WidthProperty,  new SmoothDoubleAnimation(0, ()->
//        begin
//          Result := self.ExtentWidth.Print;
//          Writeln((self.Content as Border) .Child.GetType);
//        end));
        self.BeginAnimation(SmoothResizer.HeightProperty, new SmoothDoubleAnimation(0, ()->self.ExtentHeight));
      end;
      
    end;
    
  end;
  
end.