#!/usr/bin/ruby
# Assemblage microcode SCSI SystemACE

fin=open("scsi_sd.vhs","r")
f=fin.readlines
fout=open("scsi_sd.vhd","w")
ident=""
flis=open("scsi_sd.lst","w")
flis.write("\n-- -*-vhdl-*-\n\n");

pc=0
eti=Hash.new()

# Premier passage, on détecte les étiquettes
for i in 0..f.size-1
  mmm=0
  ll=f[i].lstrip     # Supprime les espaces devant
  lob=ll.clone
  ll.sub!(/--.+/,'') # Supprime les commentaires après
  ll.rstrip!         # Supprime les espaces après
  if ll[0,1]=="%" then # si c'est un bout d'assembleur
    flis.write(pc.to_s.rjust(3))
    flis.write("   ")
    flis.write(sprintf("%X",pc).rjust(3))
    flis.write("   ")
    flis.write("  ")
    flis.write(lob)
    ll.delete!("%")
    if not (ll[1]==' ') then # si c'est une étiquette 
      ll.delete!(":")
      la=ll.scan(/\S+/)
      if la[1]==nil then mmm=1 end
      la=la[0]
      eti[la]=pc
    end
    if ll =~ /MICROCODE/ then
      next i
    end
    if mmm==0 then
      pc=pc+1
    end
  end
end

# Deuxième passage, on génère le code
mic=[]

mic.push("  TYPE type_microcode IS RECORD\n")
mic.push("    op  : enum_code;\n")
mic.push("    val : unsigned(9 DOWNTO 0);\n")
mic.push("  END RECORD;\n")
mic.push("  TYPE arr_microcode IS ARRAY(natural RANGE <>) OF type_microcode;\n\n")

mic.push("  CONSTANT microcode : arr_microcode :=(\n")
pc=0

#Opcodes
cod=[]
hcod=Hash.new()
cod.push("  TYPE enum_code IS (\n")

#Opérandes
for i in 0..f.size-1
  ll=f[i].lstrip     # Supprime les espaces devant
  ll.sub!(/--.+/,'') # Supprime les commentaires après
  ll.rstrip!         # Supprime les espaces après
  if ll[0,1]=="%" then # si c'est un bout d'assembleur
    ll.delete!("%")
    if ll =~ /MICROCODE/ then
      insert=i
      next i
    end
    par=0
    for j in 0..ll.size-1
      if (ll[j]=='(') then par=1 end
      if (ll[j]==')') then par=0 end
      if (ll[j]==' ') and par==1 then ll[j]='?' end
    end
    la=ll.scan(/\S+/)
    if ll[1]==' ' then # 32 then
      la[2]=la[1]
      la[1]=la[0]
      la[0]=nil
    end
    if la[1]==nil then
      next i
    end
    if la[1]=="LAB" then
      if eti[la[2]]==nil then 
        print "ETI ? ", la[2],"\n"
      end
      ligne="        (" + la[1].ljust(15) + ",to_unsigned(" + eti[la[2]].to_s + ",10)), \n"
    else
      ligne="        (" + la[1].ljust(15) + "," + la[2].ljust(15) + "), \n"
    end
    mic.push(ligne);
    if hcod[la[1]]==nil then
      cod.push("        " + la[1] + ",\n")
      hcod[la[1]]=1
    end
    pc=pc+1
  end
end

mic[mic.size-1].gsub!(/, /,"); ")
cod[cod.size-1].gsub!(/,/,");")

# Troisième passage, on écrit le fichier
for i in 0..f.size-1
  ll=f[i].lstrip
  if ll[0,1]=="%" then
    if ll =~ /MICROCODE/ then
      fout.puts("\n-- DEBUT Insertion Microcode\n");
      fout.puts(cod);
      fout.puts("\n");
      fout.puts(mic);
      fout.puts("\n-- FIN Insertion Microcode\n");
    end
  else
    fout.puts(f[i])
  end
end


