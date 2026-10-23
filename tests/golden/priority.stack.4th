\ приоритет операторов: * выше +, скобки группируют
\ ( x y z -- r )
: calc 
* + 
;
\ ( x y z -- r )
: grouped 
2 roll 2 roll + swap * 
;
