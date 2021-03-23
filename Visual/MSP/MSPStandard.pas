unit MSPStandard;

uses System.Windows;
uses System.Windows.Controls;
uses System.Windows.Media;

uses VUtils           in '..\VUtils';
uses DisplayListData  in '..\DisplayListData';
uses Counters         in '..\..\Backend\Counters';
uses MinimizableCore  in '..\..\Backend\MinimizableCore';

uses MSPCore;

type
  
  CounterContainer = sealed class(StackedHeap)
    
    private tb: TextBlock;
    //ToDo #2461
    public property Description: string read tb=nil?nil:tb.Text write
    begin
      if (tb<>nil) and string.IsNullOrWhiteSpace(value) then exit;
      if tb=nil then
      begin
        tb := new TextBlock;
        self.Children.Add(tb);
        tb.HorizontalAlignment  := System.Windows.HorizontalAlignment.Center;
        tb.VerticalAlignment    := System.Windows.VerticalAlignment.Center;
        tb.Margin := new Thickness(5,2,5,2);
        tb.Text := value;
      end else
      if string.IsNullOrWhiteSpace(value) then
      begin
        self.Children.Remove(tb);
        tb := nil;
      end else
        tb.Text := value;
    end;
    
    public constructor(c: Counter; descr: string);
    begin
      
      var pb := new SmoothProgressBar;
      self.Children.Add(pb);
      pb.SnapMax(1);
      c.ValueChanged += v->pb.Dispatcher.InvokeAsync(()->
      try
        pb.AnimateVal(v);
      except
        on e: Exception do
          MessageBox.Show(e.ToString);
      end);
      
      Description := descr;
    end;
    private constructor := raise new System.InvalidOperationException;
    
  end;
  
  TestInfoContainer = sealed class(ContentControl)
    private const status_w = 5;
    
    private _anchor: FrameworkElement;
    public property Anchor: FrameworkElement read _anchor;
    
    private test_sucessful: boolean? := nil;
    public property TestSucessful: boolean? read test_sucessful;
    public event TestSucessfulChanged: boolean->();
    
    private contains_sub_items := false;
    public property ContainsSubItems: boolean read contains_sub_items;
    
    public constructor(ti: TestInfo);
    begin
      
      var b := new Border;
      self._anchor := b;
      b.BorderBrush := Brushes.Black;
      b.BorderThickness := new Thickness(1);
      b.Background := Brushes.White;
      
      begin
        var sh := new StackedHeap;
        b.Child := sh;
        
        var tb := new TextBlock;
        sh.Children.Add(tb);
        tb.Margin := new Thickness(status_w+3,3,status_w+3,3);
        tb.HorizontalAlignment  := System.Windows.HorizontalAlignment.Center;
        tb.VerticalAlignment    := System.Windows.VerticalAlignment.Center;
        tb.Text := ti.DisplayName;
        ti.DisplayNameUpdated += ()->tb.Dispatcher.Invoke(()->
        begin
          tb.Text := ti.DisplayName;
        end);
        
        var status := new System.Windows.Shapes.Rectangle;
        sh.Children.Add(status);
        status.Width := 0;
        status.HorizontalAlignment := System.Windows.HorizontalAlignment.Left;
        
        if ti is RemTestInfo(var rti) then rti.TestDone += res->status.Dispatcher.Invoke(()->
        begin
          self.test_sucessful := res;
          var TestSucessfulChanged := self.TestSucessfulChanged;
          if TestSucessfulChanged<>nil then TestSucessfulChanged(res);
          status.Fill := if res then Brushes.Green else Brushes.Red;
          if status.IsDescendantOf(Application.Current.MainWindow) then
          begin
            var anim := new System.Windows.Media.Animation.DoubleAnimation(0, TestInfoContainer.status_w, new Duration(System.TimeSpan.FromSeconds(0.5)));
            status.BeginAnimation(FrameworkElement.WidthProperty, anim);
          end else
            status.Width := TestInfoContainer.status_w; var ToDo := 0; //ToDo Всё равно иногда не появляется
        end);
      end;
      
      if ti is ContainerTestInfo(var cti) then
      begin
        contains_sub_items := true;
        
        var dl := new SimpleDisplayList;
        self.Content := dl;
        dl.ItemsShift := 10;
        dl.VerticalAlignment := System.Windows.VerticalAlignment.Top;
        dl.ShowItems := false;
        dl.Header := b;
        
        cti.SubTestAdded += sub_ti->dl.Dispatcher.InvokeAsync(()->
        try
          var tic := new TestInfoContainer(sub_ti);
          dl.AddElement(tic, tic.Anchor);
        except
          on e: Exception do
            MessageBox.Show(e.ToString);
        end);
        
      end else
        self.Content := b;
      
    end;
    private constructor := raise new System.InvalidOperationException;
    
  end;
  
  LayerTestsContainer = sealed class(DisplayList<TestInfoContainer>)
    private show_err := false;
    
    protected function ShouldRenderItem(item: TestInfoContainer): boolean; override := show_err or (item.test_sucessful=nil) or item.test_sucessful.Value or item.ContainsSubItems;
    
    protected procedure HandleHeaderClick(e: System.Windows.Input.MouseButtonEventArgs); override;
    begin
      
      if e.ChangedButton = System.Windows.Input.MouseButton.Middle then
        show_err := not show_err else
        inherited;
      
      self.InvalidateMeasure;
      e.Handled := true;
    end;
    
  end;
  
  VisualMSP = sealed class(Border)
    
    public constructor;
    begin
      self.BorderBrush := new SolidColorBrush(Colors.Black);
      self.BorderThickness := new Thickness(1);
      self.Padding := new Thickness(5);
    end;
    
    protected procedure SetCounter(main_counter: MinimizationCounter; descr: string);
    begin
      var sr := new SmoothResizer;
      self.Child := sr;
      sr.SmoothX := true;
      sr.SmoothY := true;
//      sr.FillX := false;
      
      var layers_cont := new SimpleDisplayList;
      sr.Content := layers_cont;
      layers_cont.ItemsShift := 15;
      layers_cont.VerticalAlignment := System.Windows.VerticalAlignment.Top;
      
      layers_cont.Header := new CounterContainer(main_counter, descr);
      
      main_counter.LayerAdded += layer_counter->layers_cont.Dispatcher.Invoke(()->
      begin
        var sr := new SmoothResizer;
        sr.SmoothX := true;
        sr.SmoothY := true;
//        sr.FillX := false;
        
        var tests_cont := new LayerTestsContainer;
        sr.Content := tests_cont;
        tests_cont.ItemsShift := 10;
        var ToDo := 0; //ToDo привязать и к изменению размера окна
        tests_cont.MaxItemsHeight := Application.Current.MainWindow.Height*0.8;
        tests_cont.Margin := new Thickness(0,5,0,0);
        tests_cont.VerticalAlignment := System.Windows.VerticalAlignment.Top;
        
        var cc := new CounterContainer(layer_counter, nil);
        layer_counter.DisplayNameUpdated += ()->cc.Dispatcher.Invoke(()->
        begin
          cc.Description := layer_counter.DisplayName;
        end);
//        sp.Children.Add(cc);
        tests_cont.Header := cc;
        
        layer_counter.NewTestInfo += ti->cc.Dispatcher.Invoke(()->
        begin
          var tic := new TestInfoContainer(ti);
          tests_cont.AddElement(tic, tic.Anchor);
          tic.TestSucessfulChanged += ts->tests_cont.InvalidateMeasure();
        end);
        
        layers_cont.AddElement(sr, cc);
      end);
      
    end;
    
  end;
  
  StandardMSP = abstract class(MinimizationStagePart)
    protected v: VisualMSP;
    
    protected property Description: string read; abstract;
    
    protected procedure OnCounterCreated(counter: MinimizationCounter); override :=
    self.v.Dispatcher.Invoke(()->v.SetCounter(counter, self.Description));
    
    public function MakeUIElement: System.Windows.UIElement; override;
    begin
      self.v := new VisualMSP;
      Result := v;
    end;
    
  end;
  
end.