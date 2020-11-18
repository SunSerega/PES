unit BucketLoad;

uses System.Windows;
uses System.Windows.Controls;
uses System.Windows.Media;

uses PathUtils    in '..\Utils\PathUtils';

uses Testing      in '..\Backend\Testing';
uses SettingData  in '..\Backend\SettingData';

uses VUtils;
uses Common;

const BucketDir = 'Bucket';

type
  
  /// Все тесты (компиляция, запуск) для комбинации файла и компилятора
  BucketBatchTestViewer = sealed class(Border)
    private static test_mres := new Queue<System.Threading.ManualResetEvent>;
    private static curr_executing_c := 0;
    
    public constructor(first: boolean; fname, comp_fname: string; when_selected: TestResult->(); change_max_tests: integer->(); when_tested: ()->());
    begin
      self.Margin := new Thickness(10*integer(first),5,10,10);
      self.BorderThickness := new Thickness(0.5);
      self.BorderBrush := Brushes.Black;
      self.Padding := new Thickness(0,0,0,5);
      
      var sp := new StackPanel;
      self.Child := sp;
      
      var wh := new System.Threading.ManualResetEvent(false);
      lock test_mres do
      begin
        test_mres.Enqueue(wh);
        curr_executing_c += 1;
      end;
      
      System.Threading.Thread.Create(()->
      try
        var curr_test_dir := GetFullPath(
          $'{test_dir}\0\[{System.IO.Path.GetFileNameWithoutExtension(comp_fname)}] {fname.Replace(''\'',''_'')}'
        );
        change_max_tests(+2);
        
        wh.WaitOne;
        
        CopyDir(BucketDir, curr_test_dir);
        var ctr := new CompResult(curr_test_dir, fname, comp_fname);
        self.Dispatcher.Invoke(()->
        begin
          sp.Children.Add(new TestResultViewer(ctr, when_selected));
          when_tested;
        end);
        
        if ctr.ExecTestReasonable then
        begin
          var etr := new ExecResult(ctr);
          self.Dispatcher.Invoke(()->
          begin
            sp.Children.Add(new TestResultViewer(etr, when_selected));
            when_tested;
          end);
        end else
          change_max_tests(-1);
        
        while true do
        try
          System.IO.Directory.Delete(curr_test_dir, true);
          break;
        except
          on e: Exception do
          begin
            Writeln(curr_test_dir);
            Writeln(e);
            continue;
          end;
        end;
        
        lock test_mres do
        begin
          if test_mres.Count<>0 then test_mres.Dequeue.Set();
          curr_executing_c -= 1;
          if curr_executing_c=0 then
            CopyDir(BucketDir, $'{test_dir}\0\');
        end;
        
      except
        on e: Exception do MessageBox.Show(e.ToString);
      end).Start;
      
    end;
    
  end;
  
  /// Один файл
  BucketFileLoadViewer = sealed class(StackPanel)
    
    public constructor(fname: string; when_selected: TestResult->(); change_max_tests: integer->(); when_tested: ()->());
    begin
      
      var header_text := new TextBlock;
      self.Children.Add(header_text);
      header_text.Text := fname;
      header_text.Margin := new Thickness(10,5,0,0);
      
      var sp := new StackPanel;
      self.Children.Add(sp);
      sp.Orientation := System.Windows.Controls.Orientation.Horizontal;
      
      foreach var comp_fname in Settings.Current.Compilers do
        sp.Children.Add(new BucketBatchTestViewer(sp.Children.Count=0, fname, comp_fname, when_selected, change_max_tests, when_tested));
      
    end;
    
  end;
  
  /// Окно всех файлов
  BucketLoadViewer = sealed class(ScrollViewer)
    
    public constructor(when_selected: TestResult->());
    begin
      var g := new Grid;
      self.Content := g;
      
      var cd1 := new ColumnDefinition;
      cd1.Width := GridLength.Auto;
      g.ColumnDefinitions.Add(cd1);
      
      var cd2 := new ColumnDefinition;
      g.ColumnDefinitions.Add(cd2);
      
      if not System.IO.Directory.Exists(BucketDir) or not EnumerateAllFiles(BucketDir).Any then
      begin
        System.IO.Directory.CreateDirectory(BucketDir);
        Exec(BucketDir);
        Halt;
      end;
      
      var c := 0;
      foreach var fname in EnumerateAllFiles(BucketDir, '*.pas') do
      begin
        var row := new RowDefinition;
        row.Height := new GridLength(0);
        g.RowDefinitions.Add(row);
        
        var add_pb_val: integer->();
        var add_pb_max: integer->();
        
        begin
          var pb_border := new Border;
          g.Children.Add(pb_border);
          Grid.SetRow   (pb_border, c);
          Grid.SetColumn(pb_border, 1);
          pb_border.BorderThickness := new Thickness(0,1,0,1);
          pb_border.BorderBrush := new SolidColorBrush(Colors.Black);
          
          var pb := new SmoothProgressBar;
          pb_border.Child := pb;
          pb.Maximum := 0;
          
          var target_pb_val := 0;
          add_pb_val := delta->
          begin
            target_pb_val += delta;
            pb.AnimateVal(target_pb_val);
          end;
          
          var target_pb_max := 0;
          add_pb_max := delta->
          begin
            target_pb_max += delta;
            pb.AnimateMax(target_pb_max);
          end;
          
        end;
        
        begin
          var flv_border := new Border;
          g.Children.Add(flv_border);
          Grid.SetRow   (flv_border, c);
          Grid.SetColumn(flv_border, 0);
          flv_border.BorderThickness := new Thickness(0,1,0,1);
          flv_border.BorderBrush := new SolidColorBrush(Colors.Black);
          
          var flv_wrap := new SmoothResizer;
          flv_border.Child := flv_wrap;
          flv_wrap.HorizontalAlignment := System.Windows.HorizontalAlignment.Left;
          
          var flv: FrameworkElement; flv := new BucketFileLoadViewer(GetRelativePath(fname, BucketDir), when_selected,
            delta->self.Dispatcher.Invoke(()->add_pb_max.Invoke(delta)), //ToDo #2237
            ()->
            begin
              add_pb_val(1);
              if flv_wrap.Content=nil then
              begin
                flv_wrap.Content := flv;
                row.Height := GridLength.Auto;
              end;
            end
          );
          
        end;
        
        c += 1;
      end;
      
      lock BucketBatchTestViewer.test_mres do
        loop Min(BucketBatchTestViewer.test_mres.Count, System.Environment.ProcessorCount+1) do
          BucketBatchTestViewer.test_mres.Dequeue.Set();
    end;
    private constructor := raise new System.InvalidOperationException;
    
  end;
  
end.