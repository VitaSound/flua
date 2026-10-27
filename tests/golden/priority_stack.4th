\ приоритет операторов: * выше +, скобки группируют
\ @stack
\ ( x y z -- r )
: calc 
  * + 
;
\ @stack
\ ( x y z -- r )
: grouped 
  2 roll 2 roll + swap * 
;
