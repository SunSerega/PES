uses MainWindow in 'Visual\MainWindow';

{$apptype windows}

begin
  try
    Halt(System.Windows.Application.Create.Run(new PESWindow));
  except
    on e: Exception do System.Windows.MessageBox.Show(e.ToString);
  end;
end.