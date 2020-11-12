uses MainWindow in 'Visual\MainWindow';

{$apptype windows}

begin
  try
//    System.Threading.Thread.CurrentThread.CurrentUICulture := System.Globalization.CultureInfo.GetCultureInfo('en-US');
    Halt(System.Windows.Application.Create.Run(new PESWindow));
  except
    on e: Exception do System.Windows.MessageBox.Show(e.ToString);
  end;
end.