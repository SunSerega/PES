unit MSPStandard;

uses System.Windows;
uses System.Windows.Controls;
uses System.Windows.Media;

uses VUtils           in '..\VUtils';
uses DisplayListData  in '..\DisplayListData';
uses Counters         in '..\..\Backend\Counters';
uses MinimizableCore  in '..\..\Backend\MinimizableCore';
uses Testing          in '..\..\Backend\Testing';

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
  
  ITestResultApplyable = interface
    
    procedure ApplyTestResult(tr: TestResult; res: boolean);
    
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
    
    public constructor(ti: TestInfo; msp: MinimizationStagePart; m: MinimizableContainer);
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
        
        var status := new System.Windows.Shapes.Rectangle;
        sh.Children.Add(status);
        status.Width := 0;
        status.HorizontalAlignment := System.Windows.HorizontalAlignment.Left;
        
        if ti is RemTestInfo(var rti) then rti.TestDone += (tr, res)->status.Dispatcher.Invoke(()->
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
            status.Width := TestInfoContainer.status_w;
            var ToDo := 0; //ToDo Всё равно иногда не появляется
            // На самом деле возможно дело не в этом, а в том что инвалидация иногда принципиально пропускается
            // Замечал такое в других случаях, пока не прокручу вниз - status и прогресс-бар Counter-ов не обновляется
        end);
      end;
      
      var curr_head: FrameworkElement := b;
      if ti is RemTestInfo(var rti) then
      begin
        var cc := new ClickableContent;
        cc.Content := curr_head;
        
        cc.Click += (o,e)->
        if e.ChangedButton = System.Windows.Input.MouseButton.Left then
        begin
          e.Handled := true;
          var thr := new System.Threading.Thread(()->
          try
            var w := new Window;
            w.Title := $'{rti.DisplayName}: Testing...';
            rti.OnTestDone((tr, res)->w.Dispatcher.Invoke(()->(
              w.Title := if res then
                $'{rti.DisplayName}: Test Sucess' else
                $'{rti.DisplayName}: Test Failed'
            )));
            w.Content := msp.MakeTestUIElement(m, rti);
            if w.Content is ITestResultApplyable(var tra) then
              rti.OnTestDone((tr, res)->w.Dispatcher.Invoke(()->
                tra.ApplyTestResult(tr, res)
              ));
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
        end;
        
        curr_head := cc;
      end;
      if ti is ContainerTestInfo(var cti) then
      begin
        contains_sub_items := true;
        
        var dl := new SimpleDisplayList;
        dl.Header := curr_head;
        dl.ItemsShift := 10;
        dl.VerticalAlignment := System.Windows.VerticalAlignment.Top;
        dl.ShowItems := false;
        
        cti.SubTestAdded += sub_ti->dl.Dispatcher.InvokeAsync(()->
        try
          var tic := new TestInfoContainer(sub_ti, msp, m);
          dl.AddElement(tic, tic.Anchor);
        except
          on e: Exception do
            MessageBox.Show(e.ToString);
        end);
        
        curr_head := dl;
      end;
      self.Content := curr_head;
      
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
    
    protected procedure SetCounter(msp: MinimizationStagePart; main_counter: MinimizationCounter; descr: string);
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
        // На самом деле лучше трансформировать свои координаты в координаты окна
        // И сравнивать с границей экрана, чтоб ни один из дисплей листов не пытался показать что то вне экрана
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
          var tic := new TestInfoContainer(ti, msp, layer_counter.FirstNode);
          
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
    self.v.Dispatcher.Invoke(()->v.SetCounter(self, counter, self.Description));
    
    public function MakeUIElement: System.Windows.UIElement; override;
    begin
      self.v := new VisualMSP;
      Result := v;
    end;
    
  end;
  
end.