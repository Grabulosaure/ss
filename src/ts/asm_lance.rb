#!/usr/bin/ruby
# Assemblage microcode TS_LANCE


fin=open("ts_lance.vhs","r")
f=fin.readlines
fout=open("ts_lance.vhd","w")
ident=""

pc=0
eti=Hash.new()

# Premier passage, on détecte les étiquettes
for i in 0..f.size-1
  mmm=0
  ll=f[i].lstrip     # Supprime les espaces devant
  ll.sub!(/--.+/,'') # Supprime les commentaires après
  ll.rstrip!         # Supprime les espaces après
  if ll[0,1]=="%" then # si c'est un bout d'assembleur
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
mic.push("    op : enum_code;\n")
mic.push("    val : uint6;\n")
mic.push("  END RECORD;\n")
mic.push("  TYPE arr_microcode IS ARRAY(natural RANGE <>) OF type_microcode;\n\n")

mic.push("  CONSTANT microcode : arr_microcode :=(\n")
pc=0

#Opcodes
cod=[]
hcod=Hash.new()
cod.push("  TYPE enum_code IS (\n")

#Opérandes
ope=[]
hope=Hash.new()
nope=0

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
    la=ll.scan(/\S+/)
    print "   ",pc,":    ",ll ,"\n"
    if ll[1]==' ' then # 32
      la[2]=la[1]
      la[1]=la[0]
      la[0]=nil
    end
    if la[1]==nil then next i end
    if eti[la[2]]==nil then
      ligne="        (" + la[1].ljust(20) + "," + la[2] + "), --" + pc.to_s + "\n"
      if hope[la[2]]==nil then
        hope[la[2]]=nope
#        ope.push("  CONSTANT ",la[2].ljust(20)," : uint6 :=",nope,";\n");
        nope=nope+1
#        ope.push
      end
    else
      ligne="        (" + la[1].ljust(20) + "," + eti[la[2]].to_s + "), --" + pc.to_s + "\n"
    end
    mic.push(ligne)
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
      fout.puts(ope);
      fout.puts("\n");
      fout.puts(mic);
      fout.puts("\n-- FIN Insertion Microcode\n");
    end
  else
    fout.puts(f[i])
  end
end


