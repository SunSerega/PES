unit MFolder;

uses PathUtils        in '..\..\Utils\PathUtils';

uses MinimizableCore  in '..\MinimizableCore';

type
  
  MFolderFile = sealed class(MinimizableItem)
    private fname: string;
    
    public property Path: string read fname;
    
    public constructor(fname: string) :=
    self.fname := fname;
    
    public property ReadableName: string read $'File[{self.Path}]'; override;
    
  end;
  
  MFolderContents = sealed class(MinimizableList)
    private dir: string;
    
    public property Path: string read dir;
    
    public constructor(dir, base_dir: string);
    begin
      self.dir := GetRelativePath(dir, base_dir);
      
      foreach var fname in EnumerateFiles(dir) do
        items.Add(new MFolderFile(GetRelativePath(fname, base_dir)));
      
      foreach var dname in EnumerateDirectories(dir) do
        items.Add(new MFolderContents(dname, base_dir));
      
    end;
    public constructor(dir: string) := Create(dir, dir);
    
    public property ReadableName: string read $'Dir[{self.Path}]'; override;
    
    public function ContainsFile(fname: string): boolean;
    begin
      var ind := fname.IndexOf('/');
      if ind=-1 then
        self.items.OfType&<MFolderFile>.Any(mfile->mfile.Path=fname) else
      begin
        var dir_name := fname.Remove(ind);
        Result :=
          self.items.OfType&<MFolderContents>
          .First(mdir->mdir.Path=dir_name)
          .ContainsFile(fname.Remove(0, ind+1));
      end;
    end;
    
  end;
  
end.