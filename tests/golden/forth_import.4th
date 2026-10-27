\ @forth open-file ( c-addr u fam -- fileid ior )
\ @forth addrlist-add ( addr list -- )
\ ( a u fam -- r )
: load { a u fam | fid ior }
  a u fam open-file to ior to fid 
  ior 0 <> if 
    true abort" open" 
  then 
  fid 
;
\ @proc
\ ( p list -- )
: add_ptr { p list }
  p list addrlist-add 
;
